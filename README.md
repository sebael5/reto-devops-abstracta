# Despliegue de una Aplicación de Ejemplo en Kubernetes

Una aplicación web de ejemplo desplegada en Kubernetes con los fundamentos
propios de un entorno productivo: requests/limits de recursos, probes de
liveness/readiness, 2+ réplicas, actualizaciones progresivas (rolling
updates), anti-afinidad de pods, un PodDisruptionBudget, autoescalado y
acceso público mediante Ingress.

Desplegado con manifiestos planos vía `kubectl apply -f` en `manifests/` —
sin capa de templating, de modo que lo que se lee es exactamente lo que
corre en el clúster.

---

### La aplicación

[`podinfo`](https://github.com/stefanprodan/podinfo) — una pequeña aplicación
web en Go creada específicamente para demos como esta. Se eligió por sobre
un `nginx` simple porque expone endpoints HTTP **reales** de `/healthz` y
`/readyz` (de modo que los probes no son decorativos) y devuelve el nombre
de su propio pod en el cuerpo de la respuesta JSON, lo que hace trivial
*demostrar* que el Service está balanceando el tráfico entre réplicas en
lugar de golpear siempre el mismo pod.

### Requests y limits

```yaml
requests: { cpu: 50m, memory: 64Mi }
limits:   { cpu: 200m, memory: 128Mi }
```

### Réplicas, estrategia de rollout, anti-afinidad

- `replicas: 2` es el mínimo solicitado; el HPA puede llevarlo hasta 5 bajo
  carga.
- `RollingUpdate` con `maxUnavailable: 1, maxSurge: 1`: durante un despliegue,
  la capacidad nunca cae por debajo de 1 réplica lista, y como máximo se
  crea 1 pod adicional temporalmente para suavizar la transición.
- `podAntiAffinity` (preferida, no obligatoria) distribuye las réplicas
  entre distintos nodos para que la falla de un solo nodo no derribe todas
  las réplicas a la vez. Es una preferencia *suave (soft)* para que la app
  igual pueda programarse sin problemas en un clúster de un solo nodo — una
  regla `required` (dura) dejaría a la segunda réplica permanentemente en
  estado `Pending` en un clúster de desarrollo de 1 nodo, un error común y
  fácil de pasar por alto.

### Acceso público: Ingress, no LoadBalancer

El enunciado permite cualquiera de las dos opciones. Elegí **Ingress
(nginx)**:
- En un clúster local/autogestionado (este repositorio usa `kind`), un
  Service de `type: LoadBalancer` no tiene un controlador de nube que lo
  satisfaga y queda en `<pending>` para siempre, a menos que también se
  ejecute algo como MetalLB — piezas adicionales innecesarias para un
  ejercicio de código.
- Ingress es además, simplemente, el patrón más realista en producción: da
  enrutamiento por host/path y un lugar natural para terminar TLS, y
  permite que varios servicios compartan una única IP externa en lugar de
  aprovisionar un LB de nube por servicio.
- **En un clúster de nube real** (EKS/GKE/AKS) este diseño funciona sin
  cambios — el controlador de ingress de la nube aprovisiona su LB
  automáticamente. Si se prefiere específicamente un Service de tipo
  `LoadBalancer`, se incluye un ejemplo comentado al final de
  `manifests/04-ingress.yaml` — basta con cambiar el
  `ingressClassName`/las anotaciones por lo que use el controlador del
  clúster destino, y es un cambio de un solo recurso.

---

## 2. Pre-requisitos

Se necesitan tres herramientas: 
**Docker** (ejecuta los "nodos" del clúster de kind como contenedores), **kind** (crea el clúster de Kubernetes en sí)
y **kubectl** (se comunica con el clúster).

Instrucciones de instalación por sistema operativo a continuación.

### Docker

| SO | Instalación |
|---|---|
| macOS | [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) — descargar y arrastrar a Aplicaciones, luego abrirlo una vez para que arranque el daemon |
| Windows | [Docker Desktop](https://docs.docker.com/desktop/install/windows-install/) — requiere WSL2, que el instalador configurará si no está presente |
| Linux (Debian/Ubuntu) | `curl -fsSL https://get.docker.com | sh` y luego `sudo usermod -aG docker $USER`, cerrando e iniciando sesión de nuevo para poder usar `docker` sin `sudo` |
| Linux (otras distros) | Ver las [instrucciones oficiales por distribución](https://docs.docker.com/engine/install/) |

Verificar: `docker version` y `docker run hello-world` deben ejecutarse
correctamente.

### kind

`kind` es un único binario estático — no requiere gestor de paquetes,
aunque se puede usar uno si se prefiere.

| SO | Instalación |
|---|---|
| macOS (Homebrew) | `brew install kind` |
| macOS/Linux (binario) | `curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-$(uname)-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind` (usar `arm64` en lugar de `amd64` en Apple Silicon) |
| Linux (instalación con Go) | `go install sigs.k8s.io/kind@latest` (requiere Go) |
| Windows | `choco install kind` (Chocolatey), o descargar `kind-windows-amd64.exe` desde la [página de releases](https://github.com/kubernetes-sigs/kind/releases) y agregarlo al `PATH` |

Verificar: `kind version`

### kubectl

| SO | Instalación |
|---|---|
| macOS (Homebrew) | `brew install kubectl` |
| macOS (binario) | `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/` |
| Windows | `choco install kubernetes-cli`, o `curl.exe -LO "https://dl.k8s.io/release/v1.30.0/bin/windows/amd64/kubectl.exe"` y agregarlo al `PATH` |
| Linux (Debian/Ubuntu, apt) | `sudo apt-get update && sudo apt-get install -y kubectl` (requiere haber agregado antes el [repositorio apt de Kubernetes](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management)) |
| Linux (binario, cualquier distro) | `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/` |

Verificar: `kubectl version --client`

Las instrucciones oficiales completas y siempre actualizadas también están
disponibles si algo de lo anterior queda desactualizado:
[Docker](https://docs.docker.com/get-docker/),
[kind](https://kind.sigs.k8s.io/#installation-and-usage),
[kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl).

### Verificación previa al despliegue

```bash
docker version    # el daemon debe estar corriendo, no solo instalado
kind version
kubectl version --client
```
Si `docker version` se queda colgado o da error, iniciar Docker Desktop (o
`sudo systemctl start docker` en Linux) antes de ejecutar
`./scripts/deploy.sh` — kind crea sus "nodos" como contenedores de Docker,
por lo que el daemon debe estar activo primero.

## 3. Desplegar

```bash
git clone <este-repositorio>
cd k8s-app-deployment

./scripts/deploy.sh
```

Qué hace el script: crea un clúster `kind` de 3 nodos
(`kind/kind-cluster-config.yaml`), instala `ingress-nginx` (manifiesto
específico para kind, de modo que los puertos 80/443 de tu equipo se
mapean directamente al controlador de ingress) y `metrics-server` (para que
el HPA tenga datos de CPU sobre los cuales escalar), y luego aplica
`manifests/`.

Agregar a `/etc/hosts`:
```
127.0.0.1 sample-app.local
```

Probarlo:
```bash
curl http://sample-app.local/
./scripts/smoke-test.sh
```

### Paso a paso manual (equivalente al script, por si se prefiere ejecutarlo
a mano para la entrevista)

```bash
kind create cluster --name sample-app --config kind/kind-cluster-config.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl apply -f manifests/

kubectl get pods -n sample-app
kubectl get ingress -n sample-app
```

Los manifiestos en `manifests/` están numerados en orden de aplicación
(`00-namespace.yaml` hasta `06-pdb.yaml`), de modo que `kubectl apply -f
manifests/` los aplica en un orden razonable — aunque el manejo de
consistencia eventual propio de Kubernetes hace que el orden exacto rara
vez importe en la práctica (por ejemplo, el Deployment simplemente
reintentará hasta que exista el Namespace).

## 4. Verificar

```bash
kubectl get deploy,rs,pod,svc,ingress,hpa,pdb -n sample-app
kubectl describe pod -n sample-app <nombre-del-pod>   # inspeccionar el estado de los probes y los eventos
curl http://sample-app.local/
```
Al golpear la URL repetidamente debería verse distintos valores de
`hostname` en la respuesta JSON, confirmando que ambas réplicas están
recibiendo tráfico a través del Service/Ingress.

## 5. Limpieza

```bash
./scripts/cleanup.sh
```
Elimina el clúster `kind`. Dado que todo (la app, el controlador de
ingress, metrics-server) vive dentro de ese único clúster desechable, no
queda nada más por limpiar.

---

## 6. Qué haría diferente para un despliegue de producción real

Documentando recortes de alcance intencionales, ya que el enunciado pide
tanto el razonamiento como un artefacto funcional:

- **Entrega vía GitOps** (Argo CD / Flux) en lugar de `kubectl apply` desde
  una laptop — declarativo, auditable, con detección de drift.
- **Helm o Kustomize** una vez que haya más de un entorno
  (dev/staging/prod) que gestionar — para un solo entorno, los manifiestos
  planos son más simples de leer y más fáciles de defender línea por línea
  que una capa de templating, por eso decidí mantenerlo plano aquí.
- **Un registro privado + digests de imagen** en lugar de una imagen
  pública por tag, y **NetworkPolicies** para restringir el tráfico
  este-oeste — se omitieron aquí para mantener el ejercicio ejecutable en
  un solo comando.
- **cert-manager** para certificados TLS reales en el Ingress — el Ingress
  actual no tiene bloque de TLS porque necesitaría un nombre de dominio
  real y un emisor ACME para tener sentido.
- **Configuración/secretos externalizados** mediante un gestor de secretos
  adecuado si la app tuviera credenciales reales — podinfo no necesita
  ninguna aquí.
- **CI** para validar (`kubeconform`/`kubeval`) y construir/publicar
  imágenes antes de aplicar cualquier manifiesto.

## 7. Estructura del repositorio

```
.
├── kind/kind-cluster-config.yaml   # topología del clúster local
├── manifests/                      # YAML para kubectl apply (numerados = orden de aplicación)
│   ├── 00-namespace.yaml
│   ├── 01-serviceaccount.yaml
│   ├── 02-deployment.yaml
│   ├── 03-service.yaml
│   ├── 04-ingress.yaml
│   ├── 05-hpa.yaml
│   └── 06-pdb.yaml
├── scripts/
│   ├── deploy.sh
│   ├── smoke-test.sh
│   └── cleanup.sh
└── README.md
```
