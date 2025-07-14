# hk8s-gitops

GitOps repository for hk8s cluster managed by Flux CD.

## Prerequisites

Install dependencies using Homebrew:

```bash
brew bundle
```

## Setup

1. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your actual values
   ```

2. **Enable direnv** (if not already done):
   ```bash
   # Add to your shell profile
   eval "$(direnv hook bash)"  # For bash
   eval "$(direnv hook zsh)"   # For zsh

   # Allow direnv for this directory
   direnv allow
   ```

3. **Set up git hooks**:
   ```bash
   just add-githooks
   ```

4. **Generate age key for SOPS**:
   ```bash
   age-keygen -o age.agekey
   ```
   - Add the public key to `.sops.yaml`
   - Store the private key securely in 1Password
   - Update `SOPS_AGE_KEY` in `.env` to reference the 1Password item

5. **Generate configs** (if using Talos/Omni):
   ```bash
   just configs
   ```

6. **Bootstrap Flux**:
   ```bash
   flux bootstrap github \
     --owner=<your-github-org> \
     --repository=hk8s-gitops \
     --branch=main \
     --path=bootstrap
   ```

## Usage

### Managing Secrets

Edit encrypted secrets:
```bash
just edit apps/myapp/secret-database.yaml
```

Encrypt a secret file:
```bash
just encrypt apps/myapp/secret-database.yaml
```

Check for unencrypted secrets:
```bash
just check
```

### Adding Applications

1. Create namespace:
   ```bash
   # Create namespace manifest
   cat > bootstrap/namespaces/myapp.yaml <<EOF
   apiVersion: v1
   kind: Namespace
   metadata:
     name: myapp
   EOF
   ```

2. Add Helm repository (if needed):
   ```bash
   # Create repository manifest
   cat > bootstrap/helmrepositories/myapp-charts.yaml <<EOF
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: HelmRepository
   metadata:
     name: myapp-charts
     namespace: flux-system
   spec:
     interval: 15m
     url: https://charts.myapp.io
   EOF
   ```

3. Create application directory and manifests:
   ```bash
   mkdir -p apps/myapp
   # Add HelmRelease, Ingress, Secrets, etc.
   ```

## Repository Structure

```
.
├── apps/                    # Application deployments
├── bootstrap/               # Flux bootstrap configuration
│   ├── flux-system/        # Core Flux components
│   ├── helmrepositories/   # Helm repository definitions
│   └── namespaces/         # Namespace definitions
├── .githooks/              # Git hooks
├── .env.example            # Environment template
└── ...                     # Configuration files
```

## Conventions

- **File naming**: `<resource-type>-<identifier>.yaml`
- **Intervals**: GitRepository: 1m, HelmReleases: 15m
- **Secrets**: Always encrypted with SOPS
- **Namespaces**: Each app in its own namespace

See [CLAUDE.md](CLAUDE.md) for detailed style guide.
