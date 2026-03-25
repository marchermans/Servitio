# hermans-code-documents-extras

Helm chart to deploy Proton Mail Bridge for documents workflows.

## What it deploys

- A `Deployment` running `ghcr.io/videocurio/proton-mail-bridge:latest`
- A `ClusterIP` `Service` that exposes **IMAP only** on port `143`
- A `PersistentVolumeClaim` for bridge data mounted at `/root`

## Install

```bash
helm install documents-extras ./hermans-code-documents-extras
```

## Customize

- `service.port`: IMAP service port (default `143`)
- `container.imapPort`: IMAP container port (default `143`)
- `container.smtpPort`: SMTP container port inside the pod (default `25`)
- `persistence.*`: PVC configuration

## Validate

```bash
helm lint ./hermans-code-documents-extras
helm template documents-extras ./hermans-code-documents-extras
```

