# 🚀 Azure DevOps Demo — AZ-400 Portfolio Project

> **Pipeline enterprise-grade** com Azure Pipelines, AKS, Terraform e Helm.  
> Projeto de demonstração para validação prática da certificação **AZ-400 (Azure DevOps Engineer Expert)**.

---

## 📐 Arquitectura

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DEVELOPER WORKFLOW                           │
│                                                                     │
│  Git Push / PR ──► Azure Repos / GitHub                            │
└────────────────────────────┬────────────────────────────────────────┘
                             │  trigger
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CI PIPELINE (ci-pipeline.yml)                    │
│                                                                     │
│  Validate          Build              Release Notes                 │
│  ─────────         ──────             ─────────────                 │
│  flake8 lint  ──►  docker build  ──►  RELEASE.md artifact          │
│  pytest       ──►  trivy scan    ──►                                │
│  coverage     ──►  push ACR      ──►  image-tag artifact           │
└────────────────────────────┬────────────────────────────────────────┘
                             │  on success (main branch)
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 CD STAGING (cd-staging.yml)                         │
│                                                                     │
│  DeployStaging     SmokeTests          Validation                   │
│  ─────────────     ──────────          ──────────                   │
│  helm upgrade ──►  HTTP checks    ──►  Summary report               │
│  namespace    ──►  K8s readiness  ──►                               │
└────────────────────────────┬────────────────────────────────────────┘
                             │  after staging validated
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                CD PRODUCTION (cd-production.yml)                    │
│                                                                     │
│  PreFlight    ApprovalGate    DeployProd    HealthCheck             │
│  ─────────    ───────────     ──────────    ───────────             │
│  verify ACR ► MANUAL      ►  helm upgrade ► retry health           │
│  image tag    APPROVAL        --atomic       check                  │
│               REQUIRED                        │                    │
│                                               ▼                    │
│                                         Auto-Rollback               │
│                                         (if failed)                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🗂️ Estrutura do Projecto

```
azure-devops-demo/
│
├── app/
│   └── main.py                    # Flask app: /, /health, /ready, /info, /metrics
│
├── tests/
│   └── test_app.py                # pytest — cobertura completa dos endpoints
│
├── Dockerfile                     # Multi-stage build (builder + runtime non-root)
├── requirements.txt               # Flask, gunicorn, pytest, flake8
│
├── terraform/
│   ├── main.tf                    # AKS + ACR + Key Vault + Log Analytics
│   ├── variables.tf               # Todas as variáveis com validação
│   └── outputs.tf                 # Outputs usados pelos pipelines
│
├── helm/
│   └── myapp/
│       ├── Chart.yaml
│       ├── values.yaml            # Base (defaults)
│       ├── values-staging.yaml    # Override staging
│       ├── values-prod.yaml       # Override production
│       └── templates/
│           ├── _helpers.tpl
│           └── deployment.yaml    # Deploy com probes, securityContext, HPA
│
├── azure-pipelines/
│   ├── ci-pipeline.yml            # CI: lint → test → build → push ACR
│   ├── cd-staging.yml             # CD Staging: deploy → smoke tests
│   ├── cd-production.yml          # CD Production: aprovação → deploy → rollback
│   └── templates/
│       ├── build-steps.yml        # Template reutilizável: Python + pytest
│       └── deploy-steps.yml       # Template reutilizável: Helm upgrade
│
└── README.md
```

---

## ⚙️ Pré-requisitos

| Ferramenta       | Versão mínima | Propósito                          |
|------------------|---------------|------------------------------------|
| Azure CLI        | 2.58+         | Autenticação e gestão de recursos  |
| Terraform        | 1.7+          | Provisionamento de infraestrutura  |
| Helm             | 3.14+         | Deploy no AKS                      |
| kubectl          | 1.29+         | Gestão do cluster                  |
| Docker           | 24+           | Build local de imagens             |
| Python           | 3.12+         | Aplicação e testes                 |

---

## 🚀 Setup Inicial (passo a passo)

### 1. Provisionar infraestrutura com Terraform

```bash
# Login na Azure
az login
az account set --subscription "<SUBSCRIPTION_ID>"

# Criar backend de estado Terraform (apenas uma vez)
az group create --name rg-terraform-state --location westeurope
az storage account create \
  --name stterraformstatedemo \
  --resource-group rg-terraform-state \
  --location westeurope \
  --sku Standard_LRS

az storage container create \
  --name tfstate \
  --account-name stterraformstatedemo

# Inicializar e aplicar Terraform para staging
cd terraform

terraform init

terraform workspace new staging
terraform apply -var="environment=staging" -auto-approve

# Guardar outputs para uso nos pipelines
terraform output -json > ../terraform-outputs-staging.json

# Provisionar produção
terraform workspace new production
terraform apply -var="environment=production" -auto-approve
```

### 2. Configurar Azure DevOps

```bash
# Instalar extensão Azure DevOps CLI
az extension add --name azure-devops

# Configurar organização
az devops configure --defaults \
  organization=https://dev.azure.com/YOUR_ORG \
  project=azure-devops-demo
```

### 3. Criar Service Connection (Service Principal)

```bash
# Criar Service Principal com permissões mínimas
SP=$(az ad sp create-for-rbac \
  --name "sp-azdevops-demo-pipelines" \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-azdevops-demo-staging \
            /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-azdevops-demo-production \
  --sdk-auth)

echo $SP  # Usar este JSON para criar o Service Connection no Azure DevOps
```

No Azure DevOps:
1. **Project Settings** → **Service connections** → **New service connection**
2. Escolher **Azure Resource Manager** → **Service Principal (manual)**
3. Preencher com o output do comando acima
4. Nome: `azure-devops-demo-sc`

### 4. Configurar Variable Groups

```bash
# Variable Group comum (todos os ambientes)
az pipelines variable-group create \
  --name "azdevops-demo-common" \
  --variables \
    AZURE_SERVICE_CONNECTION="azure-devops-demo-sc" \
    ACR_NAME="acrazdevopsdemo<ENV>" \
    ACR_LOGIN_SERVER="acrazdevopsdemo<ENV>.azurecr.io" \
    AKS_CLUSTER_NAME="aks-azdevops-demo-<ENV>" \
    AKS_RESOURCE_GROUP="rg-azdevops-demo-<ENV>"

# Variable Group staging
az pipelines variable-group create \
  --name "azdevops-demo-staging" \
  --variables \
    STAGING_INGRESS_HOST="myapp-staging.example.com"

# Variable Group production
az pipelines variable-group create \
  --name "azdevops-demo-production" \
  --variables \
    PROD_INGRESS_HOST="myapp.example.com"
```

### 5. Configurar Environments e Approval Gates

No Azure DevOps Portal:
1. **Pipelines** → **Environments** → **New environment**
2. Criar `staging` (sem aprovação — deploy automático)
3. Criar `production` → **Approvals and checks** → **Approvals**
   - Adicionar aprovadores (team lead / tech lead)
   - Timeout: 24 horas
   - Instruções: "Verificar métricas de staging antes de aprovar"

### 6. Registar os pipelines

```bash
# CI Pipeline
az pipelines create \
  --name "azure-devops-demo-ci" \
  --yaml-path azure-pipelines/ci-pipeline.yml \
  --branch main

# CD Staging
az pipelines create \
  --name "azure-devops-demo-cd-staging" \
  --yaml-path azure-pipelines/cd-staging.yml \
  --branch main

# CD Production
az pipelines create \
  --name "azure-devops-demo-cd-production" \
  --yaml-path azure-pipelines/cd-production.yml \
  --branch main
```

### 7. Branch Policies (obrigatório para main)

```bash
# Obrigar PR com revisão para merge em main
REPO_ID=$(az repos show --repository azure-devops-demo --query id -o tsv)

az repos policy approver-count create \
  --repository-id $REPO_ID \
  --branch main \
  --is-blocking true \
  --is-enabled true \
  --minimum-approver-count 1 \
  --creator-vote-counts false

# Build validation — CI tem de passar antes do merge
az repos policy build create \
  --repository-id $REPO_ID \
  --branch main \
  --is-blocking true \
  --is-enabled true \
  --build-definition-id $(az pipelines show --name azure-devops-demo-ci --query id -o tsv) \
  --valid-duration 720
```

---

## 🔐 Gestão de Segredos

### Fluxo de Segredos

```
Azure Key Vault
     │
     │ (linked via Variable Group)
     ▼
Azure Pipelines Variable Group
     │
     │ (injectado como env var)
     ▼
Pipeline YAML (nunca exposto em texto)
     │
     │ (CSI Driver no AKS)
     ▼
Pod — montado como ficheiro / env var
```

### Segredos geridos no Key Vault

| Secret Name                  | Usado por              | Descrição                     |
|------------------------------|------------------------|-------------------------------|
| `app-db-connection-string`   | App (via CSI)          | String de ligação à DB        |
| `app-secret-key`             | App (via CSI)          | Chave secreta da aplicação    |

```bash
# Atualizar segredo no Key Vault (pipeline ou manualmente)
az keyvault secret set \
  --vault-name "kv-azdevops-demo-production" \
  --name "app-db-connection-string" \
  --value "postgresql://user:pass@host:5432/db"
```

---

## 🧪 Testes Locais

```bash
# Instalar dependências
pip install -r requirements.txt

# Lint
flake8 app/ tests/ --max-line-length=120

# Testes com cobertura
pytest tests/ -v --cov=app --cov-report=term-missing

# Executar localmente com Docker
docker build \
  --build-arg APP_VERSION=local \
  --build-arg BUILD_ID=dev \
  -t myapp:local .

docker run -p 8080:8080 \
  -e ENVIRONMENT=development \
  myapp:local

# Verificar endpoints
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/info
curl http://localhost:8080/metrics
```

---

## 🔄 Rollback Manual

```bash
# Ver histórico de releases Helm
helm history myapp-prod -n myapp-production

# Rollback para revisão anterior
helm rollback myapp-prod 0 \
  --namespace myapp-production \
  --wait \
  --timeout 5m

# Verificar estado
kubectl rollout status deployment/myapp-prod-myapp -n myapp-production
```

---

## 📊 Conceitos AZ-400 Demonstrados

| Conceito AZ-400                        | Onde está implementado                          |
|----------------------------------------|-------------------------------------------------|
| Multi-stage YAML pipelines             | `ci-pipeline.yml`, `cd-staging.yml`, `cd-production.yml` |
| Pipeline Templates (DRY)               | `templates/build-steps.yml`, `templates/deploy-steps.yml` |
| Environments + Approval Gates          | Stage `ApprovalGate` em `cd-production.yml`     |
| Variable Groups + Key Vault            | Todos os pipelines via `- group:`               |
| Service Connections (least privilege)  | `AZURE_SERVICE_CONNECTION` via Service Principal|
| Branch Policies                        | Setup em `az repos policy` acima                |
| Artifacts entre pipelines              | `image-tag` e `release-notes` artifacts         |
| Container Registry (ACR)              | Build → Push em `ci-pipeline.yml`               |
| Kubernetes deploy com Helm             | `deploy-steps.yml` com `helm upgrade --atomic`  |
| Health checks + auto-rollback          | `HealthValidation` + `AutoRollback` stages      |
| Trivy security scanning                | Stage `Build` em `ci-pipeline.yml`              |
| Infrastructure as Code (Terraform)     | `terraform/` — AKS + ACR + Key Vault           |
| Release Notes automation               | Stage `ReleaseNotes` em `ci-pipeline.yml`       |
| Zero-downtime deploy                   | `RollingUpdate` com `maxUnavailable: 0`         |
| Pod Security (non-root, read-only fs)  | `securityContext` no Helm deployment template   |

---

## 📚 Recursos Adicionais

- [AZ-400 Exam Skills Outline](https://learn.microsoft.com/en-us/certifications/exams/az-400)
- [Azure Pipelines YAML Reference](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema)
- [Azure Key Vault + Variable Groups](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups)
- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Helm --atomic flag](https://helm.sh/docs/helm/helm_upgrade/)

---

*Projecto construído para demonstração prática de competências Azure DevOps — AZ-400.*
