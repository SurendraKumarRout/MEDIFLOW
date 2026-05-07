# MediFlow — Pharma Ecommerce Platform

A production-grade microservices application for online medicine and medical equipment sales, deployed on AWS EKS.

## Repository Structure

```
mediflow/
├── Jenkinsfile                    ← CI/CD pipeline (13 stages)
├── services/                      ← Application code (7 microservices)
│   ├── user-service/              ← Authentication, user profiles (port 3001)
│   ├── product-service/           ← Medicine catalog (port 3002)
│   ├── cart-service/              ← Shopping cart via Redis (port 3003)
│   ├── payment-service/           ← Stripe payment processing (port 3004)
│   ├── order-service/             ← Order lifecycle management (port 3005)
│   ├── inventory-service/         ← Stock tracking (port 3006)
│   └── notification-service/      ← Email and SMS notifications (port 3007)
├── infrastructure/                ← Infrastructure as Code
│   └── terraform/
│       ├── bootstrap/             ← S3 + DynamoDB for state (run once)
│       ├── modules/               ← Reusable Terraform modules
│       │   ├── vpc/               ← Networking foundation
│       │   ├── eks/               ← Kubernetes cluster
│       │   ├── rds/               ← PostgreSQL database
│       │   └── elasticache/       ← Redis cache
│       └── environments/          ← Environment-specific configs
│           ├── dev/               ← Dev environment
│           ├── staging/           ← Staging environment
│           └── prod/              ← Production environment
└── helm-charts/                   ← Kubernetes deployment charts
    ├── user-service/
    ├── product-service/
    ├── cart-service/
    ├── order-service/
    ├── payment-service/
    ├── inventory-service/
    └── notification-service/

```

## Services

| Service | Port | Database | Purpose |
|---------|------|----------|---------|
| User Service | 3001 | PostgreSQL | Authentication, user profiles |
| Product Service | 3002 | PostgreSQL | Medicine catalog and search |
| Cart Service | 3003 | Redis | Shopping cart management |
| Payment Service | 3004 | PostgreSQL | Stripe payment processing |
| Order Service | 3005 | PostgreSQL | Order lifecycle and orchestration |
| Inventory Service | 3006 | PostgreSQL | Stock tracking |
| Notification Service | 3007 | PostgreSQL + RabbitMQ | Email and SMS |

## Tech Stack

- **Runtime:** Node.js 18 with Express
- **Databases:** PostgreSQL (via Sequelize ORM), Redis
- **Message Queue:** RabbitMQ (topic exchange)
- **Payment:** Stripe
- **Logging:** Winston (JSON logs → CloudWatch)
- **Container:** Docker (multi-stage builds)
- **Orchestration:** AWS EKS (Kubernetes)
- **Registry:** AWS ECR
- **CI/CD:** Jenkins (13-stage pipeline)
- **Deployment:** Helm
- **Infrastructure:** Terraform

## CI/CD Pipeline (13 Stages)

| Stage | Description | Runs On |
|-------|-------------|---------|
| 1. Checkout | Clone code | All branches |
| 2. Run Tests | Unit tests, npm audit, linting | All branches |
| 3. SonarQube | Code quality + security | All branches |
| 4. Build Images | Docker multi-stage build | develop, main |
| 5. Trivy Scan | Vulnerability scanning | develop, main |
| 6. Push to ECR | Push images to AWS registry | develop, main |
| 7. Deploy Dev | Helm deploy to dev cluster | develop only |
| 8. Deploy Staging | Helm deploy to staging cluster | main only |
| 9. Approval | Manual approval gate | main only |
| 10. Deploy Prod | Helm deploy to prod cluster | main only |
| 11. Health Check | Verify all pods healthy | main only |
| 12. Smoke Tests | Basic functionality tests | main only |
| 13. Notify | Slack + email notification | All branches |

## Infrastructure Setup Order

```
1. Manually create S3 buckets (for Terraform state)
2. Manually create DynamoDB table (for state locking)
3. Manually create Jenkins EC2 instance with IAM role
4. Run: cd infrastructure/terraform/environments/dev && terraform init && terraform apply
5. Run: cd infrastructure/terraform/environments/staging && terraform init && terraform apply
6. Run: cd infrastructure/terraform/environments/prod && terraform init && terraform apply
```

## Environment Comparison

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| EKS Nodes | t3.medium x2 | t3.large x2 | t3.xlarge x3 |
| Max Nodes | 3 | 4 | 10 |
| RDS | db.t3.micro | db.t3.small | db.t3.medium |
| Redis | cache.t3.micro | cache.t3.small | cache.t3.medium |
| Multi-AZ | No | No | Yes |
| Deletion Protection | No | No | Yes |

---
*MediFlow — Your Trusted Healthcare Partner*
