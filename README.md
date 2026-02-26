# eb-deploy - Deploy Scripts

Public repository containing installation and update scripts for the application.
Artifacts are stored in a **private** Azure Blob Storage container and are never committed here.

## Repository structure

```
scripts/
├── install.sh      - Full installation of the application
├── update.sh       - Update to a new version
├── rollback.sh     - Rollback to the previous backup
├── healthcheck.sh  - Verify the application is healthy
└── README.md       - This file
```


## Required environment variables

| Variable                | Description                                        |
|-------------------------|----------------------------------------------------|
| `AZURE_STORAGE_ACCOUNT` | Azure Storage account name                         |
| `AZURE_CONTAINER_NAME`  | Blob container name where artifacts are stored     |
| `SAS_TOKEN`             | SAS token for blob access (injected at runtime)    |
| `APP_DIR`               | Target installation directory (default `/app`)     |
| `BACKUP_DIR`            | Backup directory for rollback (default `/app-backup`) |
| `APP_URL`               | Application base URL for health checks             |

> **Important:** Never commit secrets, SAS tokens, or credentials to this repository.
> All sensitive values must be injected at runtime via environment variables or a secrets manager.

## Usage

```bash
# Install interactively (select component/version)
export AZURE_SAS_TOKEN="?your_sas_token"
./install.sh

# Update interactively (select component/version)
export AZURE_SAS_TOKEN="?your_sas_token"
./update.sh

# Roll back interactively (select component/version)
./rollback.sh

# Check application health
APP_URL=http://localhost:3000 ./healthcheck.sh
```

## Notes

- Artifact storage is private (Azure Blob Storage). This repo contains only the scripts.
- No CI/CD workflows are defined here. Pipelines are managed externally.
- No source code of the application is stored in this repository.
