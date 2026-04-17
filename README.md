# InfraFlow – Infrastructure DevOps Microservices

[![CI/CD Pipeline](https://github.com/Folong-zidane/InfraFlow_devops/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/Folong-zidane/InfraFlow_devops/actions/workflows/ci-cd.yml)

Infrastructure microservices complète composée de deux services :
- **api-service** : API REST JSON (nginx:alpine) exposant `/get`, `/post`, `/status`
- **web-service** : Reverse proxy Nginx qui route les requêtes vers l'api-service

Déployable en local via **Docker Compose** (développement) ou **Kubernetes** (production), avec pipeline **CI/CD GitHub Actions** automatisé et stack de monitoring **Prometheus + Grafana**.

---

## Comment ça fonctionne

```
Internet / Client
      │
      ▼
┌─────────────────┐
│   web-service   │  nginx:alpine – port 8080 (hôte) → 80 (container)
│  Reverse Proxy  │  Route / → api-service:8080
│  /status → 200  │  /status → réponse locale JSON
└────────┬────────┘
         │ réseau Docker : infraflow-net
         ▼
┌─────────────────┐
│   api-service   │  nginx:alpine – port 8080 (interne uniquement)
│    API REST     │  /get  → JSON  |  /post → JSON  |  /status → JSON
└─────────────────┘
```

- Le **web-service** est le seul point d'entrée exposé sur l'hôte (port 8080)
- L'**api-service** n'est accessible que depuis le réseau interne Docker/Kubernetes
- Les deux services tournent en **utilisateur non-root** pour la sécurité
- Les **health checks** garantissent que web-service ne démarre qu'après que api-service soit prêt

---

## Prérequis

| Outil | Version | Installation |
|-------|---------|-------------|
| Docker + Docker Compose | 24.x+ | [docs.docker.com](https://docs.docker.com/get-docker/) |
| kubectl | 1.28+ | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| minikube **ou** kind | latest | [minikube.sigs.k8s.io](https://minikube.sigs.k8s.io/docs/start/) |
| helm | 3.x+ | [helm.sh](https://helm.sh/docs/intro/install/) |
| bash | 4.x+ | Inclus sur Linux/macOS |

Vérifier que tout est installé :
```bash
docker --version && docker compose version
kubectl version --client
minikube version
helm version
```

---

## Démarrage rapide – Docker Compose

> Temps estimé : **2 minutes**

```bash
# 1. Cloner le dépôt
git clone https://github.com/Folong-zidane/InfraFlow_devops.git
cd InfraFlow_devops

# 2. Créer le fichier de configuration
cp .env.example .env

# 3. Démarrer toute l'infrastructure en une commande
docker compose up -d

# 4. Vérifier que les deux services sont healthy
docker compose ps
```

Résultat attendu :
```
NAME          STATUS
api-service   Up X seconds (healthy)
web-service   Up X seconds (healthy)
```

### Tester les endpoints

```bash
# Via le proxy web-service (point d'entrée principal)
curl http://localhost:8080/get
# → {"service":"api-service","method":"GET","status":"ok","url":"/get"}

curl http://localhost:8080/status
# → {"status":"ok","service":"web-service"}

curl http://localhost:8080/post
# → {"service":"api-service","method":"POST","status":"ok","url":"/post"}
```

### Arrêter l'infrastructure

```bash
docker compose down
# Avec suppression des volumes :
docker compose down -v
```

---

## Déploiement Kubernetes

> Temps estimé : **5 minutes** (hors téléchargement des images)

### Étape 1 – Démarrer le cluster local

```bash
# Avec minikube (recommandé)
minikube start

# Ou avec kind
kind create cluster --name infraflow
```

### Étape 2 – Lancer le script de déploiement automatisé

```bash
bash scripts/deploy.sh
```

Le script effectue automatiquement dans l'ordre :
1. Vérifie que `kubectl`, `helm` et `docker` sont disponibles dans le PATH
2. Vérifie la connexion au cluster Kubernetes
3. Crée le namespace `infraflow` s'il n'existe pas
4. Applique les manifestes dans le bon ordre (ConfigMap → Deployments → Services → HPA)
5. Attend que tous les pods soient `Ready` (`kubectl rollout status`)
6. Déploie Prometheus + Grafana via Helm dans le namespace `monitoring`
7. Affiche les URLs d'accès et l'état des pods

### Étape 3 – Vérifier le déploiement

```bash
# État des pods
kubectl get pods -n infraflow

# Résultat attendu :
# NAME                           READY   STATUS    RESTARTS
# api-service-xxxx-yyyy          1/1     Running   0
# api-service-xxxx-zzzz          1/1     Running   0
# web-service-xxxx-yyyy          1/1     Running   0
# web-service-xxxx-zzzz          1/1     Running   0

# État des services
kubectl get svc -n infraflow

# HPA (autoscaling)
kubectl get hpa -n infraflow
```

### Étape 4 – Accéder aux services

```bash
# Option A – Via NodePort (minikube)
minikube service web-service -n infraflow --url
# Puis : curl <url-affichée>/get

# Option B – Via port-forward
kubectl port-forward svc/web-service 8080:80 -n infraflow &
curl http://localhost:8080/get
```

### Déploiement manuel (sans le script)

```bash
# Appliquer tous les manifestes
kubectl apply -f k8s/namespace.yml
kubectl apply -f k8s/web-service/configmap.yml
kubectl apply -f k8s/api-service/deployment.yml
kubectl apply -f k8s/api-service/service.yml
kubectl apply -f k8s/api-service/hpa.yml
kubectl apply -f k8s/web-service/deployment.yml
kubectl apply -f k8s/web-service/service.yml

# Attendre que les pods soient prêts
kubectl rollout status deployment/api-service -n infraflow
kubectl rollout status deployment/web-service -n infraflow
```

---

## Monitoring – Prometheus + Grafana

### Installation via Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace --wait
```

### Accéder à Grafana

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Ouvrir [http://localhost:3000](http://localhost:3000)
- Login : `admin`
- Mot de passe : `prom-operator`

Aller dans **Dashboards → Browse → Kubernetes / Compute Resources / Namespace (Pods)**
Filtrer sur le namespace `infraflow` pour voir CPU et mémoire.

### Accéder à Prometheus

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Ouvrir [http://localhost:9090](http://localhost:9090)

### Alertes configurées

Les alertes sont définies dans `k8s/prometheus-rules.yml` :

| Alerte | Condition | Sévérité |
|--------|-----------|----------|
| `PodDown` | Pod non-ready depuis > 1 minute | CRITICAL |
| `HighCPUUsage` | CPU > 80% depuis > 2 minutes | WARNING |
| `HighMemoryUsage` | Mémoire > 85% depuis > 2 minutes | WARNING |

Vérifier les alertes dans Prometheus : **Alerts** → filtrer `infraflow`

---

## Pipeline CI/CD – GitHub Actions

Le pipeline se déclenche automatiquement sur :
- `push` vers la branche `main`
- `pull_request` vers `main`

### Les 4 jobs

```
push/PR
  │
  ▼
lint-and-test          ← Hadolint (Dockerfiles) + yamllint + ShellCheck
  │ succès
  ▼
build                  ← Build images Docker taguées avec le SHA du commit
  │ succès
  ▼
security-scan          ← Scan Trivy – bloque si vulnérabilité CRITICAL
  │ succès + branche main
  ▼
push                   ← Push vers GHCR (GitHub Container Registry)
```

### Images publiées

Après un push sur `main`, les images sont disponibles sur GHCR :
```
ghcr.io/folong-zidane/api-service:<sha-commit>
ghcr.io/folong-zidane/api-service:stable
ghcr.io/folong-zidane/web-service:<sha-commit>
ghcr.io/folong-zidane/web-service:stable
```

### Secrets requis

Aucun secret supplémentaire à configurer — le pipeline utilise `GITHUB_TOKEN` fourni automatiquement par GitHub Actions pour s'authentifier sur GHCR.

---

## Structure du projet

```
InfraFlow_devops/
├── .github/
│   └── workflows/
│       └── ci-cd.yml          # Pipeline : lint → build → scan → push
│
├── api-service/
│   ├── Dockerfile             # nginx:alpine, non-root (appuser), port 8080
│   └── api.conf               # Config nginx : /get /post /status → JSON
│
├── web-service/
│   ├── Dockerfile             # nginx:alpine, non-root (nginxuser), port 80
│   └── nginx.conf             # Reverse proxy → api-service:8080 + /status
│
├── k8s/
│   ├── namespace.yml          # Namespace : infraflow
│   ├── prometheus-rules.yml   # Alertes PrometheusRule (PodDown, CPU, Mémoire)
│   ├── api-service/
│   │   ├── deployment.yml     # replicas:2, probes, resources, securityContext
│   │   ├── service.yml        # ClusterIP port 8080
│   │   └── hpa.yml            # HPA CPU 70%, min:2 max:10
│   └── web-service/
│       ├── deployment.yml     # replicas:2, probes, resources, securityContext
│       ├── service.yml        # NodePort 30080
│       └── configmap.yml      # Config nginx montée en volume
│
├── scripts/
│   └── deploy.sh              # Déploiement automatisé complet
│
├── docker-compose.yml         # Stack locale complète
├── .env.example               # Template des variables d'environnement
├── .dockerignore              # Exclusions pour les builds Docker
├── .gitignore                 # Exclusion du .env local
└── README.md
```

---

## Variables d'environnement

Copier `.env.example` en `.env` avant de lancer `docker compose up` :

```bash
cp .env.example .env
```

| Variable | Défaut | Description |
|----------|--------|-------------|
| `REGISTRY` | `ghcr.io` | Registry Docker |
| `IMAGE_OWNER` | `infraflow` | Namespace/owner des images |
| `IMAGE_TAG` | `latest` | Tag des images |
| `WEB_PORT` | `8080` | Port exposé sur l'hôte pour web-service |

> Le fichier `.env` ne doit jamais être commité — il est dans `.gitignore`.

---

## Sécurité

- Tous les containers tournent en **utilisateur non-root**
- `securityContext` : `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities: drop: ALL`
- **Aucun secret en dur** dans les fichiers (Dockerfile, YAML, scripts)
- Credentials CI/CD via `GITHUB_TOKEN` (GitHub Actions Secrets)
- **Scan Trivy** dans la CI — pipeline bloqué sur toute vulnérabilité CRITICAL
- **Hadolint** sans erreur CRITICAL sur les Dockerfiles
- Tag `:latest` jamais utilisé en production — SHA du commit utilisé

---

## Dépannage

**Les services ne démarrent pas :**
```bash
docker compose logs api-service
docker compose logs web-service
```

**Un pod Kubernetes est en CrashLoopBackOff :**
```bash
kubectl describe pod <nom-du-pod> -n infraflow
kubectl logs <nom-du-pod> -n infraflow
```

**Le HPA ne scale pas :**
```bash
# Activer metrics-server sur minikube
minikube addons enable metrics-server
kubectl top pods -n infraflow
```

**Réinitialiser complètement :**
```bash
# Docker
docker compose down -v

# Kubernetes
kubectl delete namespace infraflow
kubectl delete namespace monitoring
```

---
