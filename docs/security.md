# Security Configuration

This document describes the security hardening applied to the dm-nkp-gitops-custom-app deployments.

## Security Best Practices Implemented

Based on [kubesec perfect score example](https://github.com/deepak-muley/dm-nkp-gitops-infra/blob/main/docs/kubesec-perfect-score-example.yaml), the following security measures have been implemented:

### 1. AppArmor Profile
- **Pod-level**: `appArmorProfile.type: RuntimeDefault` (Currently commented out for kind cluster compatibility)
- **Container-level**: `appArmorProfile.type: RuntimeDefault` (Currently commented out for kind cluster compatibility)
- **Annotation**: `container.apparmor.security.beta.kubernetes.io/app: runtime/default` (Currently commented out)

**Note**: AppArmor is currently disabled in the manifests because kind clusters don't have AppArmor enabled by default. To enable AppArmor when deploying to clusters that support it, uncomment the `appArmorProfile` sections in:
- `chart/dm-nkp-gitops-custom-app/values.yaml`
- `chart/dm-nkp-gitops-custom-app/templates/deployment.yaml`
- `manifests/base/deployment.yaml`

AppArmor provides application-level access control, restricting what programs can do.

### 2. Seccomp Profile
- **Pod-level**: `seccompProfile.type: RuntimeDefault`
- **Container-level**: `seccompProfile.type: RuntimeDefault`

Seccomp restricts the system calls available to containers, reducing the attack surface.

### 3. User Namespaces (Kubernetes 1.25+)
- **Pod-level**: `hostUsers: false`

Isolates UIDs from the host, preventing UID collisions and improving security.

### 4. High UID Group
- **Pod-level**: `runAsGroup: 65534` (nobody group, >10000)
- **Container-level**: `runAsGroup: 65534`
- **Pod-level**: `fsGroup: 65534`

Using high UIDs (>10000) reduces the risk of conflicts with system users.

### 5. Run as Non-Root
- **Pod-level**: `runAsNonRoot: true`, `runAsUser: 65532`
- **Container-level**: `runAsNonRoot: true`, `runAsUser: 65532`

Running containers as non-root users limits the impact of potential security breaches.

### 6. Drop ALL Capabilities
- **Container-level**: `capabilities.drop: [ALL]`

Removes all Linux capabilities, ensuring containers have minimal privileges.

### 7. Read-Only Root Filesystem
- **Container-level**: `readOnlyRootFilesystem: true`

Prevents writes to the root filesystem. Writable directories are mounted as volumes:
- `/tmp` - temporary files
- `/var/run` - runtime data
- `/var/log` - log files

### 8. Additional Security Settings
- **Container-level**: `allowPrivilegeEscalation: false`
- **Container-level**: `privileged: false`

Prevents privilege escalation and running in privileged mode.

### 9. ServiceAccount Token (Optional)
- **Pod-level**: `automountServiceAccountToken: true/false`

Set to `false` if the pod doesn't need Kubernetes API access. Default is `true` for compatibility.

## Kubesec Scanning

### Local Scanning

Scan base manifests:
```bash
make kubesec
```

Scan rendered Helm chart:
```bash
make kubesec-helm
```

### CI/CD Integration

Kubesec scans are automatically run in GitHub Actions:
- Scans base Kubernetes manifests
- Scans rendered Helm chart templates
- Fails the build if security issues are found

### Kubesec Score Target

The deployment is configured to achieve a **9/9 kubesec score** by implementing all security best practices.

## Security Context Configuration

### Pod Security Context
```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
  appArmorProfile:
    type: RuntimeDefault
  runAsGroup: 65534
  fsGroup: 65534
  runAsNonRoot: true
  runAsUser: 65532
  hostUsers: false
```

### Container Security Context
```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
  appArmorProfile:
    type: RuntimeDefault
  runAsGroup: 65534
  runAsNonRoot: true
  runAsUser: 65532
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  privileged: false
```

## Volume Mounts for Read-Only Filesystem

When using `readOnlyRootFilesystem: true`, writable directories must be mounted as volumes:

```yaml
volumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: var-run
    mountPath: /var/run
  - name: var-log
    mountPath: /var/log

volumes:
  - name: tmp
    emptyDir: {}
  - name: var-run
    emptyDir: {}
  - name: var-log
    emptyDir: {}
```

## Customization

Security settings can be customized in `chart/dm-nkp-gitops-custom-app/values.yaml`:

```yaml
podSecurityContext:
  runAsUser: 65532
  runAsGroup: 65534
  # ... other settings

securityContext:
  readOnlyRootFilesystem: true
  # ... other settings
```

## References

- [Kubesec Perfect Score Example](https://github.com/deepak-muley/dm-nkp-gitops-infra/blob/main/docs/kubesec-perfect-score-example.yaml)
- [Kubesec Documentation](https://kubesec.io/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

