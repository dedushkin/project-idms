# 0. Предварительные требования
* Кластер Kubernetes с минимум 3 рабочими нодами
* Установлен и настроен CNI плагин. В примере для простоты будем использовать [Calico в режиме VXLAN инкапсуляции](https://docs.tigera.io/calico/latest/networking/configuring/vxlan-ipip)
* Настроена реализация сервисов с типом LoadBalancer. В примере будем использовать [MetalLB](https://metallb.universe.tf/installation/)
* Установлен и настроен [cert-manager](https://cert-manager.io/) с двумя Issuer - для выпуска самоподписанных сертификатов и Let's Encrypt

## Ресурсы Calico
```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        blockSize: 26
        cidr: 10.244.0.0/16
        encapsulation: VXLAN
        natOutgoing: Enabled
        nodeSelector: all()

---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}

---
apiVersion: operator.tigera.io/v1
kind: Goldmane
metadata:
  name: default

---
apiVersion: operator.tigera.io/v1
kind: Whisker
metadata:
  name: default
```

## Ресурсы MetalLB

```yaml
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.11.0.0/28
  avoidBuggyIPs: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: local-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - local-pool
```

# 1. Настройка Envoy Gateway

Так как используем CNI Calico, устанавливать отдельно Envoy Gateway не потребуется - воспользуемся его встроенной реализацией [Calico Ingress Gateway](https://docs.tigera.io/calico/latest/networking/ingress-gateway/about-calico-ingress-gateway)

Создадим два класса Gateway: один для публично доступных ресурсов, второй - для тех, что доступны только через Netbird.

`kubectl create -f ./kubernetes-manifests/envoy-gatewayclasses.yaml`

И два Gateway:

`kubectl create -f ./kubernetes-manifests/envoy-gateways.yaml`

# 2. Подготовка к развертыванию БД

Для развертывания PostgreSQL понадобятся Persistent Volume, поэтому установим [Local Path Provisioner](https://github.com/rancher/local-path-provisioner):

```bash
helm repo add containeroo https://charts.containeroo.ch

helm upgrade --install local-path-storage --create-namespace --namespace local-path-storage --version 0.0.34 containeroo/local-path-provisioner -f ./helm/values/local-path-provisioner.yaml
```

Затем установим оператор CloudNativePG:

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts

helm upgrade --install cnpg --create-namespace --namespace cnpg-system --version 0.27.1 cnpg/cloudnative-pg
```

# 3. Развертывание Netbird Control Plane

Для начала создадим кластер PostgreSQL с настроенным резервным копированием в S3 бакет:

```bash
helm upgrade --install netbird-database --create-namespace --namespace netbird --version 0.6.0 cnpg/cluster -f ./helm/values/pg-netbird.yaml
```

Теперь установим Netbird Control Plane. Для рендеринга файла конфигурации добавим sidecar-контейнер к нашему деплойменту.

Заменяем поля конфига с секретами на переменные окружения `${EXAMPLE_ENV_VAR}` и помещаем их в секреты, затем init-контейнер с envsubst подготовит итоговый конфиг.

Генерация ключей, которые нужно указать в values-файле:

**authSecret**: `openssl rand -base64 32 | sed "s/=//g"`
**datastoreEncryptionKey**: `openssl rand -base64 32`

```bash
helm repo add idms https://raw.githubusercontent.com/dedushkin/project-idms/main/helm/charts

helm upgrade --install netbird --namespace netbird idms/netbird -f ./helm/values/netbird.yaml
```

После установки логинимся и выпускаем в интерфейсе Netbird токен для сервис-аккаунта с правами администратора. Его нужно будет указать в values-файле оператора и в переменных Terraform.

# 4. Развертывание Keycloak

Для Keycloak создадим отдельный кластер PostgreSQL:

```bash
helm upgrade --install keycloak-database --create-namespace --namespace keycloak --version 0.6.0 cnpg/cluster -f ./helm/values/pg-keycloak.yaml
```

Затем устанавливаем оператор и Keycloak:

```bash
helm upgrade --install keycloak --namespace keycloak idms/keycloak-operator -f ./helm/values/keycloak.yaml
```

# 5. Конфигурация Netbird и Keycloak

Выполняется через Terraform. Необходимо указать значения переменных в `.tfvars`.

```bash
cd terraform
terraform init
terraform plan --var-file=.tfvars -out=.tfplan
terraform apply ".tfplan"
```

Для следующих шагов понадобятся секреты из Outputs, сохраним их:

```bash
terraform output midpoint_password
terraform output netbird_initial_password
terraform output grafana_client_secret
terraform output gitlab_client_secret
```

Авторизуемся в Netbird с помощью учетных данных: `netbird_initial_username` и `netbird_initial_password`. Это нужно для проверки работы SSO и автоматического создания групп.

Затем устанавливаем и настраиваем Netbird Operator:

```bash
helm upgrade --install netbird-operator --create-namespace --namespace netbird-operator idms/kubernetes-operator -f ./helm/values/netbird-operator.yaml

helm upgrade --install netbird-operator-config --namespace netbird-operator idms/netbird-operator-config -f ./helm/values/netbird-operator-config.yaml
```

# 6. Развертывание MidPoint

Для MidPoint создадим отдельный кластер PostgreSQL:

```bash
helm upgrade --install midpoint-database --create-namespace --namespace midpoint --version 0.6.0 cnpg/cluster -f ./helm/values/pg-midpoint.yaml
```

Затем необходимо сгенерировать хранилище сертификатов для MidPoint. Оно должно быть одинаковое для всех реплик. 
Для этого запустим под с MidPoint, инициализируем хранилище, добавим туда SSL сертификат для подключения к Keycloak и создадим секрет:

## Добавление сертификата для соединения с Keycloak

```bash
kubectl run -n keycloak --image=midpoint:latest midpoint-0 \
  --overrides='
  {
    "apiVersion": "v1",
    "spec": {
      "containers": [{
        "name": "midpoint",
        "image": "evolveum/midpoint:latest",
        "command": ["/bin/bash"],
        "args": ["-c", "/opt/midpoint/bin/midpoint.sh init-native && /opt/midpoint/bin/midpoint.sh start && sleep 99999"],
        "env": [{
          "name": "MP_INIT_CFG",
          "value": "/opt/midpoint/var"
        }],
        "volumeMounts": [{
          "name": "keycloak-ca",
          "mountPath": "/opt/midpoint/var/certs"
        }]
      }],
      "volumes": [{
        "name": "keycloak-ca",
        "secret": {
          "secretName": "keycloak-tls-secret"
        }
      }]
    }
  }'

kubectl exec -n keycloak midpoint-0 -- \
keytool -keystore /opt/midpoint/var/keystore.jceks \
-storetype jceks \
-storepass changeit \
-import -alias servercert \
-trustcacerts -noprompt \
-file /opt/midpoint/var/certs/ca.crt

kubectl cp midpoint-0:/opt/midpoint/var/keystore.jceks ./keystore.jceks

kubectl create secret generic midpoint-keystore -n midpoint --from-file=keystore.jceks
```

Также нужно внести Client Secret клиента Midpoint в values в файле `001-security-policy.xml` и пароль пользователя Midpoint в Keycloak (из `terraform output midpoint_password`) в файле `002-keycloak-connector.xml` конфигмапы midpoint-import-objects.

После этого устанавливаем MidPoint:

```bash
helm upgrade --install midpoint --namespace midpoint idms/midpoint -f ./helm/values/midpoint.yaml
```

Для проверки создадим пользователя, привязываем его к Keycloak, добавляем роль End User и пробуем авторизоваться по ссылке https://midpoint.lab.dedushk.in/midpoint/auth/gui-oidc

# 7. Настройка Gitlab

Добавляем конфигурацию в `gitlab.rb`:

```ruby
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = true
gitlab_rails['omniauth_sync_email_from_provider'] = 'openid_connect'
gitlab_rails['omniauth_sync_profile_from_provider'] = ['openid_connect']
gitlab_rails['omniauth_sync_profile_attributes'] = ['email']
gitlab_rails['omniauth_auto_sign_in_with_provider'] = 'openid_connect'
gitlab_rails['omniauth_providers'] = [
  {
    name: "openid_connect", # do not change this parameter
    label: "Keycloak",
    args: {
      name: "openid_connect",
      scope: ["openid","profile","email"],
      response_type: "code",
      issuer: "https://keycloak.lab.dedushk.in/realms/lab",
      discovery: true,
      client_auth_method: "query",
      uid_field: "preferred_username",
      send_scope_to_token_endpoint: "false",
      pkce: true,
      client_options: {
        identifier: "gitlab",
        secret: "changeme",
        redirect_uri: "https://gitlab.lab.dedushk.in/users/auth/openid_connect/callback"
      }
    }
  }
]
```

Для применения изменений `gitlab-ctl reconfigure`

# 8. Развертывание мониторинга

```bash
helm upgrade --install --create-namespace --namespace kube-prometheus-stack kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 82.9.0 --values ./helm/values/monitoring.yaml
```

Подключим SSO к Grafana, для этого добавим конфигурацию в `grafana.ini`:

```ini
[server]
domain = 'grafana.lab.dedushk.in'
root_url = 'https://grafana.lab.dedushk.in'
[auth.generic_oauth]
enabled = true
name = Keycloak-OAuth
allow_sign_up = true
client_id = grafana
client_secret = changeme
scopes = openid email profile offline_access roles
email_attribute_path = email
login_attribute_path = preferred_username
name_attribute_path = name
auth_url = https://keycloak.lab.dedushk.in/realms/lab/protocol/openid-connect/auth
token_url = https://keycloak.lab.dedushk.in/realms/lab/protocol/openid-connect/token
api_url = https://keycloak.lab.dedushk.in/realms/lab/protocol/openid-connect/userinfo
signout_redirect_url = https://keycloak.lab.dedushk.in/realms/lab/protocol/openid-connect/logout?post_logout_redirect_uri=https%3A%2F%2Fgrafana.lab.dedushk.in%2Flogin
role_attribute_path = contains(roles[*], 'grafanaadmin') && 'GrafanaAdmin' || contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'editor') && 'Editor' || contains(roles[*], 'viewer') && 'Viewer'
role_attribute_strict = true
allow_assign_grafana_admin = true
use_refresh_token = true
oauth_allow_insecure_email_lookup = true
[auth]
token_rotation_interval_minutes = 1
```

Важно, чтобы в переменной окружения `GF_SERVER_ROOT_URL=https://grafana.lab.dedushk.in` был корректный URL, иначе переадресация при входе будет работать неправильно.

# 9. Резервное копирование

Для резервного копирования установим Velero:

```bash
kubectl create namespace velero

# Это файл с ключами доступа к S3 бакету, в котором будут храниться бэкапы
kubectl create secret generic velero-credentials -n velero --from-file=aws=credentials

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts/

helm upgrade --install --namespace velero my-velero vmware-tanzu/velero --version 12.0.0 -f ./helm/values/velero.yaml
```