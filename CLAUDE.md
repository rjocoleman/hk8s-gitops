# GitOps Repository Style Guide

This guide defines the conventions and patterns for developing Kubernetes GitOps repositories using Flux CD, SOPS encryption, and Justfile automation. Follow these guidelines to maintain consistency across environments.

## Repository Structure

### Directory Layout

```
.
├── apps/                           # Application deployments
│   └── <app-name>/                # One directory per application
│       ├── helmrelease-<app>.yaml # Helm release definition
│       ├── ingress-<app>.yaml     # Ingress configuration
│       ├── secret-<purpose>.yaml  # Encrypted secrets
│       └── *.yaml                 # Other K8s resources
├── bootstrap/                      # Flux bootstrap configuration
│   ├── flux-system/               # Core Flux components (managed by Flux)
│   ├── helmrepositories/          # Helm repository definitions
│   └── namespaces/                # Namespace definitions
├── .githooks/                      # Git hooks for automation
│   └── pre-commit                 # Pre-commit validation
├── justfile                       # Task automation
├── Brewfile                       # Homebrew dependencies
├── .sops.yaml                     # SOPS encryption configuration
├── .yamllint.yaml                 # YAML linting rules
├── .yamlfmt                       # YAML formatting config
├── .env.example                   # Example environment variables
├── .envrc                         # Direnv configuration
├── .gitignore                     # Git ignore patterns
├── kubeconfig.tmpl.yaml           # Kubeconfig template (optional)
├── talosconfig.tmpl.yaml          # Talos config template (optional)
├── omniconfig.tmpl.yaml           # Omni config template (optional)
├── CLAUDE.md                      # This style guide
└── README.md                      # Repository documentation
```

### Directory Conventions

1. **apps/**: Each application gets its own directory containing all related manifests
2. **bootstrap/**: Contains Flux system configuration and controllers
3. **One directory per concern**: Keep related resources together

## Flux Configuration

### Default Behavior

Flux processes all YAML files in the repository by default. Only create Kustomization resources when you need:
- Custom decryption settings for specific directories
- Health checks for critical deployments
- Different sync intervals for specific apps
- Post-build variable substitution or generators

### HelmRelease Resources

Location: `apps/<app-name>/helmrelease-<app-name>.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app-name> # Match app directory name
  namespace: <app-namespace> # App's namespace, not flux-system
spec:
  interval: 15m # Standard interval
  timeout: 5m # 5m for Helm operations
  releaseName: <app-name> # Match metadata.name
  chart:
    spec:
      chart: <chart-name>
      version: ~<major>.<minor> # Allow patch updates (e.g., ~1.2)
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
        namespace: flux-system # Repos are in flux-system
  values: # Inline values, not separate files
    <helm-values>
```

### HelmRepository Resources

Location: `bootstrap/helmrepositories/<provider>.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <provider-name> # e.g., prometheus-community
  namespace: flux-system # Always flux-system
spec:
  interval: 15m # Standard interval
  url: <repository-url>
```

### Namespace Definitions

Location: `bootstrap/namespaces/<app-name>.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <app-name> # Match app directory name
```

## Naming Conventions

### File Naming

- **HelmRelease**: `helmrelease-<app-name>.yaml`
- **Ingress**: `ingress-<app-name>.yaml` or `ingress-<service>.yaml`
- **Secrets**: `secret-<purpose>.yaml` or `<app>-secrets.yaml`
- **ConfigMaps**: `configmap-<purpose>.yaml`
- **Services**: `service-<name>.yaml`
- **General pattern**: `<resource-type>-<identifier>.yaml`

### Resource Naming

- Use lowercase with hyphens (kebab-case)
- Be descriptive but concise
- Maintain consistency within app boundaries
- Match directory names where applicable

## SOPS Encryption

### Configuration

Create `.sops.yaml` in repository root:

```yaml
creation_rules:
  - age: <age-public-key>

stores:
  yaml:
    indent: 2
  json:
    indent: 2
  json_binary:
    indent: 2
```

### Secret Structure

Only values under `data` or `stringData` are encrypted:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name> # Unencrypted
  namespace: <namespace> # Unencrypted
type: Opaque
data:
  username: <encrypted-value> # Encrypted
  password: <encrypted-value> # Encrypted
```

### Encryption Commands

All secrets MUST be encrypted before committing. Use the justfile commands.

## Justfile Conventions

### Complete Justfile

```make
# Edit encrypted file with SOPS
edit file:
    op run -- sops {{file}}

# Encrypt file in place
encrypt file:
    op run -- sops --encrypt --encrypted-regex '^(data|stringData)$' --in-place {{file}}

# Decrypt file (use carefully)
decrypt file:
   op run -- sops --decrypt --in-place {{file}}

# Check for unencrypted secrets in staged files
check *FILES:
    #!/usr/bin/env bash
    set -euo pipefail
    IFS=$'\n\t'

    # Filter YAML files from the passed arguments
    yaml_files=$(echo "{{ FILES }}" | tr ' ' '\n' | grep -E '\.(yaml|yml)$' || true)

    # Check each file for unencrypted secrets
    unencrypted_files=""
    for file in $yaml_files; do
        if grep -q '^kind: Secret' "$file" && ! grep -q 'sops:' "$file"; then
            unencrypted_files+="$file"$'\n'
        fi
    done

    if [ -n "$unencrypted_files" ]; then
        echo "The following files contain unencrypted or improperly encrypted secrets:"
        echo "$unencrypted_files"
        echo "Please use SOPS to encrypt these files before committing."
        exit 1
    fi

    echo "All secret manifests are properly encrypted."
    exit 0

# Install git hooks
add-githooks:
    git config core.hooksPath .githooks

# Generate kubeconfig from template
kubeconfig:
    envsubst < kubeconfig.tmpl.yaml > kubeconfig.yaml

# Generate talosconfig from template
talosconfig:
    envsubst < talosconfig.tmpl.yaml > talosconfig.yaml

# Generate omniconfig from template
omniconfig:
    envsubst < omniconfig.tmpl.yaml > omniconfig.yaml

# Generate all configs
configs: kubeconfig talosconfig omniconfig
    @echo "All configs generated"

# Clean generated configs
clean-configs:
    rm -f kubeconfig.yaml talosconfig.yaml omniconfig.yaml
```

### Integration with 1Password (for SOPS only)

- Use `op run --` prefix for SOPS commands
- Store age private key in 1Password
- Reference via environment variable: `SOPS_AGE_KEY="op://vault/item/field"`
- Config templates use simple `envsubst` with environment variables

## Standard Configurations

### Intervals

- GitRepository: `1m0s`
- HelmReleases: `15m`
- HelmRepositories: `15m`

### Timeouts

- HelmReleases: `5m`

### Common Settings

- Use specific minor version constraints for Helm charts (e.g., `~1.2` for 1.2.x)
- Embed Helm values directly in HelmRelease

## Best Practices

### Resource Organization

1. **One app per directory**: Keep all related resources together
2. **Bootstrap order**: namespaces → repositories → applications
3. **Let Flux handle discovery**: Avoid creating Kustomization resources unless needed

### Security

1. **Always encrypt secrets**: Use SOPS for all Secret resources
2. **Never commit plaintext secrets**: Use pre-commit hooks to verify
3. **Separate secret files**: Keep secrets in dedicated files for easier management
4. **Use least privilege**: Scope resources to appropriate namespaces

### Flux Patterns

1. **Single source of truth**: Let Flux discover resources automatically
2. **Namespace isolation**: Apps deploy to their own namespaces
3. **Flux resources in flux-system**: Keep Flux components separate
4. **Consistent intervals**: Use standard intervals unless specific requirements exist

### Maintenance

1. **Document decisions**: Update README for significant changes
2. **Version flexibility**: Use tilde ranges (~) for Helm charts to allow patch updates
3. **Clean pruning**: Flux automatically prunes removed resources

## Example Application Structure

For a new application "myapp":

```
apps/myapp/
├── helmrelease-myapp.yaml         # If using Helm
├── deployment-myapp.yaml          # If using raw manifests
├── service-myapp.yaml
├── ingress-myapp.yaml
├── secret-database.yaml           # Encrypted with SOPS
└── configmap-myapp-config.yaml

bootstrap/namespaces/myapp.yaml
bootstrap/helmrepositories/myapp-charts.yaml  # If needed
```

## Validation

Before committing:

1. Run `just check` to verify secrets are encrypted
2. Run `yamllint` on YAML files to check for syntax issues
3. Run `yamlfmt` to ensure consistent formatting
4. Ensure file naming follows conventions
5. Verify resources deploy to correct namespaces
6. Check that Flux can reconcile changes

## Environment Configuration

### .env.example

Create `.env.example` with the following template:

```bash
# SOPS age key from 1Password
SOPS_AGE_KEY="op://Vault/sops-age-key/age.agekey"

# Editor for SOPS (examples: "code -w", "vim", "nano")
EDITOR="code -w"

# Kubernetes configs (optional, for local development)
KUBECONFIG="${PWD}/kubeconfig.yaml"
TALOSCONFIG="${PWD}/talosconfig.yaml"
OMNICONFIG="${PWD}/omniconfig.yaml"

# Talos/Omni config variables (only 3 needed!)
TALOS_ORG_NAME="your-org"
TALOS_CLUSTER_NAME="your-cluster"
TALOS_IDENTITY="your-identity@example.com"
```

### .envrc (for direnv)

Create `.envrc` for automatic environment loading:

```bash
# Load environment variables
dotenv

# Set kubeconfig path relative to this directory
export KUBECONFIG="${PWD}/kubeconfig.yaml"
export TALOSCONFIG="${PWD}/talosconfig.yaml"
export OMNICONFIG="${PWD}/omniconfig.yaml"

# Optional: Add scripts to PATH
PATH_add scripts

# Optional: Show loaded confirmation
echo "GitOps environment loaded"
echo "KUBECONFIG set to: $KUBECONFIG"
```

### .gitignore

Essential gitignore entries:

```gitignore
# Environment files
.env
.env.local

# Direnv
.direnv

# Generated configs (contain secrets)
kubeconfig.yaml
talosconfig.yaml
omniconfig.yaml

# SOPS temporary files
*.dec
*.tmp

# Editor/IDE files
.vscode/
.idea/
*.swp
*.swo
*~

# OS files
.DS_Store
Thumbs.db

# Backup files
*.bak
*.backup

age.agekey
```

## Git Hooks

### Pre-commit Hook

Create `.githooks/pre-commit`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Running pre-commit checks..."

# Get list of staged YAML files
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(yaml|yml)$' || true)

if [ -n "$staged_files" ]; then
    # Check for unencrypted secrets using the same validation as 'just check'
    echo "Checking for unencrypted secrets..."
    if ! just check $staged_files; then
        exit 1
    fi

    # Run yamllint
    echo "Running yamllint..."
    if ! yamllint $staged_files; then
        echo "❌ Pre-commit check failed: YAML linting errors found"
        echo "Run 'yamllint <file>' to see detailed errors"
        exit 1
    fi

    # Run yamlfmt and check if files were modified
    echo "Running yamlfmt..."
    for file in $staged_files; do
        # Store original content
        original=$(cat "$file")

        # Run yamlfmt
        yamlfmt "$file" || {
            echo "❌ Pre-commit check failed: yamlfmt error on $file"
            exit 1
        }

        # Check if file was modified
        if [ "$original" != "$(cat "$file")" ]; then
            echo "❌ Pre-commit check failed: $file needs formatting"
            echo "Run 'yamlfmt $file' to fix formatting"
            git checkout -- "$file"  # Restore original
            exit 1
        fi
    done
fi

echo "✅ Pre-commit checks passed"
```

Make it executable: `chmod +x .githooks/pre-commit`

### YAML Formatting Configuration

Create `.yamllint.yaml` for yamllint configuration:

```yaml
extends: default
rules:
  line-length:
    max: 120
    level: warning
  comments:
    min-spaces-from-content: 1
  indentation:
    spaces: 2
    indent-sequences: consistent
  document-start: disable
  truthy:
    allowed-values: ["true", "false", "yes", "no"]
```

Create `.yamlfmt` for yamlfmt configuration:

```yaml
formatter:
  type: basic
  indent: 2
  include_document_start: false
  scan_folded_as_literal: true
  retain_line_breaks: true
  drop_merge_tag: true
  pad_line_comments: 1
```

## Config Templates

### kubeconfig.tmpl.yaml

Template for Kubernetes config (Omni-based):

```yaml
apiVersion: v1
kind: Config
clusters:
  - cluster:
      server: https://${TALOS_ORG_NAME}.kubernetes.omni.siderolabs.io
    name: ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}
contexts:
  - context:
      cluster: ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}
      namespace: default
      user: ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}-${TALOS_IDENTITY}
    name: ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}
current-context: ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}
users:
  - name: ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}-${TALOS_IDENTITY}
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1beta1
        args:
          - oidc-login
          - get-token
          - --oidc-issuer-url=https://${TALOS_ORG_NAME}.omni.siderolabs.io/oidc
          - --oidc-client-id=native
          - --oidc-extra-scope=cluster:${TALOS_CLUSTER_NAME}
        command: kubectl
        env: null
        provideClusterInfo: false
```

### talosconfig.tmpl.yaml

Template for Talos config:

```yaml
context: ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}
contexts:
  ${TALOS_ORG_NAME}-${TALOS_CLUSTER_NAME}:
    endpoints:
      - https://${TALOS_ORG_NAME}.omni.siderolabs.io
    auth:
      siderov1:
    identity: ${TALOS_IDENTITY}
    cluster: ${TALOS_CLUSTER_NAME}
```

### omniconfig.tmpl.yaml

Template for Omni config:

```yaml
contexts:
  default:
    url: https://${TALOS_ORG_NAME}.omni.siderolabs.io
    auth:
      siderov1:
        identity: ${TALOS_IDENTITY}
context: default
```

## Initial Setup

### Brewfile

Create `Brewfile` for dependency management:

```ruby
# Taps
tap "fluxcd/tap"
tap "siderolabs/tap"

# Core tools
brew "just"           # Task automation
brew "age"            # Encryption tool for SOPS
brew "gettext"        # Provides envsubst
brew "sops"           # Secret management
brew "direnv"         # Environment variable management

# Kubernetes tools
brew "kubectl"        # Kubernetes CLI
brew "fluxcd/tap/flux" # Flux CLI
brew "helm"           # Helm package manager
brew "kustomize"      # Kubernetes configuration management

# YAML tools
brew "yamllint"       # YAML linter
brew "yamlfmt"        # YAML formatter
brew "yq"             # YAML processor

# Optional but recommended
brew "jq"             # JSON processor
brew "ripgrep"        # Fast text search
brew "kubelogin"      # Kubernetes OIDC authentication

# Talos/Omni tools (if using)
brew "siderolabs/tap/talosctl"  # Talos CLI
brew "siderolabs/tap/omnictl"   # Omni CLI

# Casks
cask "1password-cli"  # Optional, for SOPS key management
```

### Prerequisites

Install all dependencies:

```bash
# Install Homebrew dependencies
brew bundle
```

### Repository Setup

When creating a new repository:

1. **Initialize Git hooks**:

   ```bash
   mkdir -p .githooks
   # Create pre-commit hook (see above)
   chmod +x .githooks/pre-commit
   just add-githooks
   ```

2. **Setup environment**:

   ```bash
   cp .env.example .env
   # Edit .env with your values
   ```

3. **Configure direnv**:

   ```bash
   # Enable direnv in your shell (add to ~/.bashrc or ~/.zshrc)
   eval "$(direnv hook bash)"  # For bash
   eval "$(direnv hook zsh)"   # For zsh

   # Allow direnv for this directory
   direnv allow

   # Verify environment is loaded
   echo $KUBECONFIG  # Should show ./kubeconfig.yaml
   ```

4. **Create SOPS config**:

   ```bash
   # Generate age key pair
   age-keygen -o age.agekey
   # Add public key to .sops.yaml
   # Store private key in 1Password
   ```

5. **Generate configs** (if using Talos/Omni):

   ```bash
   just configs
   ```

6. **Bootstrap Flux**:
   ```bash
   flux bootstrap github \
     --owner=<org> \
     --repository=<repo> \
     --branch=main \
     --path=bootstrap
   ```

This style guide ensures consistency, security, and maintainability across GitOps repositories.
