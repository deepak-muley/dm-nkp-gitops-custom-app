# Documentation Guide - Learning Path

**Welcome!** This guide organizes all documentation into a clear learning sequence. Read documents in order for a progressive learning experience.

---

## 🚀 Quick Start (Read First)

**Start here if you're new:**

1. **[Quick Start](QUICK_START.md)** - 5-minute bootstrap guide
   - Install prerequisites
   - Build and run locally
   - Basic verification

2. **[Core Application & Telemetry](../../README.md#core-application--telemetry)** - What the app does
   - What the core app code does (5 min read)
   - How metrics, logs, and traces are generated
   - Quick reference

3. **[OpenTelemetry Quick Start](OPENTELEMETRY_QUICK_START.md)** - Telemetry setup
   - OpenTelemetry basics
   - How to deploy with observability stack
   - Access Grafana dashboards

---

## 📚 Learning Paths

Choose your path based on what you want to learn:

### Path 1: Core Application Development (Beginner → Advanced)

**Goal:** Understand and work with the application code

1. **[Development Guide](development.md)** - Local development setup
   - Code structure
   - Adding new metrics/endpoints
   - Testing workflow

2. **[Metrics Documentation](metrics.md)** - Understanding metrics
   - Available metrics
   - Prometheus queries
   - Adding custom metrics

3. **[Testing Guide](testing.md)** - All testing approaches
   - Unit tests
   - Integration tests
   - E2E tests

### Path 2: Observability & Monitoring (Beginner → Advanced)

**Goal:** Set up and understand monitoring stack

1. **[Grafana Beginner Guide](GRAFANA_BEGINNER_GUIDE.md)** ⭐ **READ THIS FIRST**
   - What are dashboards, datasources, providers
   - How auto-discovery works
   - Step-by-step setup

2. **[OpenTelemetry Quick Start](OPENTELEMETRY_QUICK_START.md)** - Quick setup
   - Deploy observability stack
   - Configure data sources
   - View dashboards

3. **[OpenTelemetry Workflow](opentelemetry-workflow.md)** - Deep dive
   - Architecture details
   - Data flow (metrics, logs, traces)
   - Troubleshooting

4. **[Duplicate Log Collection](DUPLICATE_LOG_COLLECTION.md)** ⚠️ **IMPORTANT**
   - How to avoid duplicate logs when Logging Operator is deployed
   - OTel Collector vs Logging Operator configuration
   - Storage impact and best practices

5. **[Logging Operator Default Behavior](LOGGING_OPERATOR_DEFAULT_BEHAVIOR.md)** - Collection scope
   - Does it collect all namespaces by default?
   - How exclusions work (labels, Flow CRs, ClusterFlow CRs)
   - How to check what's being collected in your environment

### Path 3: Deployment & Operations (Intermediate → Advanced)

**Goal:** Deploy and operate the application

1. **[Deployment Guide](DEPLOYMENT_GUIDE.md)** - Production deployment
   - Kubernetes deployment
   - Helm charts
   - Configuration

2. **[Helm Chart Installation](HELM_CHART_INSTALLATION_REFERENCE.md)** - Helm reference
   - Chart structure
   - Values files
   - Customization

3. **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues
   - Build issues
   - Deployment issues
   - Monitoring issues

### Path 4: CI/CD & Automation (Intermediate → Advanced)

**Goal:** Set up and understand CI/CD pipelines

1. **[CI/CD Pipeline](cicd-pipeline.md)** - Complete pipeline overview
   - All workflows explained
   - Jobs and steps
   - Best practices

2. **[GitHub Actions Setup](github-actions-setup.md)** - Setup guide
   - Repository setup
   - Secrets configuration
   - Workflow configuration

3. **[GitHub Actions Reference](github-actions-reference.md)** - All workflows
   - Detailed workflow documentation
   - Configuration options
   - Triggers and conditions

### Path 5: End-to-End Testing (Intermediate)

**Goal:** Run and understand E2E tests

1. **[E2E Quick Reference](E2E_QUICK_REFERENCE.md)** - Quick start
   - Final command: `make e2e-tests`
   - Prerequisites
   - Access Grafana after tests

2. **[Running E2E Tests](RUNNING_E2E_TESTS_LOCALLY.md)** - Detailed guide
   - Complete workflow
   - What gets tested
   - Troubleshooting

### Path 6: Security & Best Practices (Intermediate → Advanced)

**Goal:** Understand security and best practices

1. **[Security Guide](security.md)** - Security practices
   - Image signing
   - Vulnerability scanning
   - Best practices

2. **[Production Ready Checklist](production-ready-checklist.md)** - Pre-production checklist
   - Security checklist
   - Performance checklist
   - Monitoring checklist

3. **[Image Signing](image-signing.md)** - Signing images
   - Cosign setup
   - Signing workflow
   - Verification

---

## 📖 Reference Documents (Read as Needed)

These documents provide specific reference information:

### Architecture & Design

- **[Architecture Decision Records (ADRs)](adr/)** - Technical decisions
  - ADR-0001: Record Architecture Decisions
  - ADR-0002+: Technology and design choices

- **[Manifests vs Helm Charts](manifests-vs-helm.md)** - Deployment approaches
  - When to use manifests
  - When to use Helm charts
  - Comparison

### Platform & Dependencies

- **[Platform Dependencies](PLATFORM_DEPENDENCIES.md)** - What platform provides
  - Pre-deployed services
  - Namespace structure
  - Service endpoints

- **[Platform Helm Chart Dependencies](PLATFORM_HELM_CHART_DEPENDENCIES.md)** - Helm dependencies
  - Chart dependencies
  - Installation order
  - Configuration

### Development Tools

- **[Buildpacks Guide](buildpacks.md)** - Container builds
  - What are buildpacks
  - How they work
  - Usage

- **[Pre-commit Setup](pre-commit-setup.md)** - Code quality hooks
  - Installation
  - Configuration
  - Hooks available

- **[golangci-lint Setup](golangci-lint-setup.md)** - Linting setup
  - Configuration
  - Rules
  - Usage

### GitHub & Collaboration

- **[GitHub Roles](github-roles.md)** - Repository permissions
  - Role descriptions
  - Access levels
  - Best practices

- **[Branch Protection](branch-protection.md)** - Branch rules
  - Protection rules
  - Required reviews
  - Status checks

- **[Commit Signing](commit-signing.md)** - GPG signing
  - Setup GPG keys
  - Configure Git
  - Verification

- **[PAT Setup](pat-setup.md)** - Personal Access Tokens
  - Create tokens
  - Usage
  - Security

### Advanced Topics

- **[Model Repository Template](model-repository-template.md)** - Replicate this setup
  - Complete guide
  - All files explained
  - Replication checklist

- **[Replication Checklist](REPLICATION_CHECKLIST.md)** - Step-by-step replication
  - Checklist format
  - All steps
  - Verification

- **[Verification Guide](verification.md)** - Verify setup
  - Build verification
  - Deployment verification
  - Monitoring verification

---

## 🗂️ Topic Categories

### 🎯 Application Core
- `development.md` - Development setup and workflow
- `metrics.md` - Metrics documentation
- `testing.md` - Testing guide

### 📊 Observability & Monitoring
- `GRAFANA_BEGINNER_GUIDE.md` ⭐ - **Start here for Grafana**
- `OPENTELEMETRY_QUICK_START.md` - OpenTelemetry quick setup
- `opentelemetry-workflow.md` - Complete OpenTelemetry workflow
- `DUPLICATE_LOG_COLLECTION.md` ⚠️ - **Avoid duplicate logs** (OTel vs Logging Operator)
- `LOGGING_OPERATOR_DEFAULT_BEHAVIOR.md` - **Logging Operator collection scope & exclusions**
- `grafana.md` - Grafana dashboard guide (reference)

### 🚀 Deployment
- `DEPLOYMENT_GUIDE.md` - Complete deployment guide
- `helm-deployment.md` - Helm deployment details
- `HELM_CHART_INSTALLATION_REFERENCE.md` - Helm chart reference
- `manifests-vs-helm.md` - Deployment approaches comparison

### 🔄 CI/CD
- `cicd-pipeline.md` - Complete CI/CD pipeline
- `github-actions-setup.md` - GitHub Actions setup
- `github-actions-reference.md` - All workflows documented
- `github-actions-summary.md` - Quick reference

### 🧪 Testing
- `E2E_QUICK_REFERENCE.md` - Quick E2E reference
- `RUNNING_E2E_TESTS_LOCALLY.md` - Detailed E2E guide
- `E2E_DEMO.md` - Step-by-step demo

### 🔒 Security
- `security.md` - Security practices
- `image-signing.md` - Image signing
- `openssf-scorecard.md` - Security scorecard

### 🏗️ Architecture
- `adr/` - Architecture Decision Records
- `model-repository-template.md` - Template guide
- `REPLICATION_CHECKLIST.md` - Replication steps

### 🛠️ Tools & Setup
- `buildpacks.md` - Container builds
- `pre-commit-setup.md` - Pre-commit hooks
- `golangci-lint-setup.md` - Linting setup
- `ghcr-artifacts.md` - Container registry

### 🤝 Collaboration
- `github-roles.md` - Repository roles
- `branch-protection.md` - Branch protection
- `commit-signing.md` - GPG signing
- `pat-setup.md` - Personal access tokens

### 📦 Platform & Dependencies
- `PLATFORM_DEPENDENCIES.md` - Platform services
- `PLATFORM_HELM_CHART_DEPENDENCIES.md` - Helm dependencies

---

## ⚠️ Deprecated/Consolidated Documents

The following documents have been consolidated or are duplicates. **Don't read these** - read the consolidated versions above instead:

### ❌ Consolidated into `GRAFANA_BEGINNER_GUIDE.md`:
- ~~`GRAFANA_DASHBOARDS_SETUP.md`~~ - Merged into beginner guide
- ~~`GRAFANA_DASHBOARDS_COMPLETE.md`~~ - Merged into beginner guide
- ~~`grafana.md`~~ - Kept as reference, but start with beginner guide

### ❌ Consolidated into `E2E_QUICK_REFERENCE.md`:
- ~~`E2E_DEMO.md`~~ - Keep as detailed guide, but start with quick reference
- ~~`E2E_TESTING_UPDATE.md`~~ - Historical, skip
- ~~`E2E_UPDATE_SUMMARY.md`~~ - Historical, skip
- ~~`RUNNING_E2E_TESTS.md`~~ - Duplicate of `RUNNING_E2E_TESTS_LOCALLY.md`

### ❌ Consolidated into `OPENTELEMETRY_QUICK_START.md`:
- ~~`OBSERVABILITY_COMPLETE.md`~~ - Historical summary, skip
- ~~`OBSERVABILITY_STACK_COMPLETE.md`~~ - Historical summary, skip
- ~~`OBSERVABILITY_STACK_CLARIFICATION.md`~~ - Historical clarification, skip
- ~~`README_OBSERVABILITY.md`~~ - Consolidated into quick start

### ❌ Consolidated into `PLATFORM_DEPENDENCIES.md`:
- ~~`LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES.md`~~ - Historical, skip
- ~~`LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES_SUMMARY.md`~~ - Historical, skip
- ~~`LOGGING_OPERATOR_EXPLANATION.md`~~ - Historical, skip

### ❌ Consolidated into `github-actions-reference.md`:
- ~~`github-actions-summary.md`~~ - Quick reference only, read main doc

### ❌ Historical/Summary Documents (Skip):
- ~~`COMPLETE_SETUP_SUMMARY.md`~~ - Historical summary
- ~~`COMPLETE_WORKFLOW.md`~~ - Historical summary
- ~~`SETUP_COMPLETE.md`~~ - Historical summary
- ~~`MIGRATION_SUMMARY.md`~~ - Historical migration notes
- ~~`DOCUMENTATION_ORGANIZATION.md`~~ - Internal organization doc (this is now the index!)

### ❌ Internal/Meta Documents (Skip):
- ~~`markdownlint-fixes.md`~~ - Internal formatting guide
- ~~`VIDEO_DEMO_SCRIPT.md`~~ - Demo script template
- ~~`VIDEO_RECORDING_CHECKLIST.md`~~ - Demo checklist
- ~~`WHY_SEPARATE_OBSERVABILITY_STACK.md`~~ - Historical explanation

### ❌ Specialized/Advanced (Read only if needed):
- `dependabot-auto-merge.md` - Advanced: Auto-merge setup
- `local-testing-signing.md` - Advanced: Local signing setup
- `nodejs-setup.md` - Specialized: Node.js setup (if you're working with JS tools)
- `workflow.md` - Advanced: Complete workflow details
- `agents.md` - Advanced: AI agent guidance

---

## 🎓 Recommended Reading Order for Beginners

**If you're completely new, follow this order:**

1. **[Quick Start](QUICK_START.md)** (5 min)
   - Get the app running locally

2. **[Core Application & Telemetry](../../README.md#core-application--telemetry)** (10 min)
   - Understand what the app does
   - Learn how telemetry works

3. **[Grafana Beginner Guide](GRAFANA_BEGINNER_GUIDE.md)** (20 min) ⭐
   - Understand dashboards and monitoring
   - Learn how auto-discovery works

4. **[OpenTelemetry Quick Start](OPENTELEMETRY_QUICK_START.md)** (15 min)
   - Deploy full observability stack
   - See metrics, logs, traces in Grafana

5. **[Development Guide](development.md)** (15 min)
   - Learn code structure
   - Understand how to add features

6. **[E2E Quick Reference](E2E_QUICK_REFERENCE.md)** (5 min)
   - Run end-to-end tests
   - Verify everything works

**Total time: ~70 minutes** to bootstrap yourself!

---

## 🎯 Quick Reference by Task

**"I want to..."**

- **...get started quickly**: Read `QUICK_START.md` → `OPENTELEMETRY_QUICK_START.md`
- **...understand monitoring**: Read `GRAFANA_BEGINNER_GUIDE.md` → `opentelemetry-workflow.md`
- **...deploy to production**: Read `DEPLOYMENT_GUIDE.md` → `HELM_CHART_INSTALLATION_REFERENCE.md`
- **...set up CI/CD**: Read `github-actions-setup.md` → `cicd-pipeline.md`
- **...run tests**: Read `E2E_QUICK_REFERENCE.md` → `RUNNING_E2E_TESTS_LOCALLY.md`
- **...understand the code**: Read `development.md` → `metrics.md`
- **...avoid duplicate logs**: Read `DUPLICATE_LOG_COLLECTION.md` (OTel vs Logging Operator)
- **...troubleshoot issues**: Read `TROUBLESHOOTING.md`
- **...replicate this setup**: Read `model-repository-template.md` → `REPLICATION_CHECKLIST.md`

---

## 💡 Tips

1. **Start with Quick Start** - Don't skip this!
2. **Read Beginner Guides first** - They explain concepts simply
3. **Skip historical documents** - Marked with ❌ above
4. **Use search** - Most docs have a table of contents
5. **Read troubleshooting** - If something doesn't work, check `TROUBLESHOOTING.md` first

---

**Questions?** Check `TROUBLESHOOTING.md` or open an issue.
