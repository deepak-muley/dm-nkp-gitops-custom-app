# GitHub Repository Roles and Permissions

This document explains the different roles and permission levels available in GitHub repositories.

## Repository Permission Levels

GitHub provides five permission levels for repository access:

### 1. Read (Lowest)

**What they can do:**

- ✅ View repository content
- ✅ Clone repository
- ✅ Download releases
- ✅ View issues and pull requests
- ✅ Comment on issues and PRs

**What they cannot do:**

- ❌ Push code
- ❌ Create branches
- ❌ Modify repository settings
- ❌ Manage issues/PRs

**Use case:** Viewers, external contributors who only need to see code

### 2. Triage

**What they can do:**

- ✅ Everything from Read
- ✅ Manage issues and pull requests (labels, milestones, assignees)
- ✅ Close/reopen issues and PRs
- ✅ Mark issues as duplicates

**What they cannot do:**

- ❌ Push code
- ❌ Create branches
- ❌ Merge pull requests
- ❌ Modify repository settings

**Use case:** Community managers, issue triagers, project coordinators

### 3. Write

**What they can do:**

- ✅ Everything from Triage
- ✅ Push code to non-protected branches
- ✅ Create branches
- ✅ Create and edit files
- ✅ Merge pull requests (if allowed by branch protection)

**What they cannot do:**

- ❌ Push to protected branches (without PR)
- ❌ Modify repository settings
- ❌ Delete repository
- ❌ Manage collaborators

**Use case:** Regular developers, contributors who need to write code

### 4. Maintain

**What they can do:**

- ✅ Everything from Write
- ✅ Manage repository settings (some)
- ✅ Manage repository variables and secrets
- ✅ Manage repository environments
- ✅ Manage repository actions

**What they cannot do:**

- ❌ Delete repository
- ❌ Transfer repository
- ❌ Modify branch protection rules
- ❌ Manage collaborators
- ❌ Modify repository visibility

**Use case:** Senior developers, team leads, CI/CD managers

### 5. Admin (Highest)

**What they can do:**

- ✅ Everything from Maintain
- ✅ Modify all repository settings
- ✅ Modify branch protection rules
- ✅ Manage collaborators and teams
- ✅ Delete repository
- ✅ Transfer repository
- ✅ Modify repository visibility

**What they cannot do (with `enforce_admins` enabled):**

- ❌ Push directly to protected branches
- ❌ Bypass branch protection rules
- ❌ Force push to protected branches

**What they can still do (even with `enforce_admins`):**

- ✅ Modify branch protection rules (via Settings)
- ✅ Access repository settings
- ✅ Manage collaborators

**Use case:** Repository owners, organization admins, senior maintainers

## Permission Comparison Table

| Action | Read | Triage | Write | Maintain | Admin |
|--------|------|--------|-------|----------|-------|
| View code | ✅ | ✅ | ✅ | ✅ | ✅ |
| Comment on issues/PRs | ✅ | ✅ | ✅ | ✅ | ✅ |
| Manage issues/PRs | ❌ | ✅ | ✅ | ✅ | ✅ |
| Push code | ❌ | ❌ | ✅ | ✅ | ✅ |
| Merge PRs | ❌ | ❌ | ✅* | ✅* | ✅* |
| Modify settings | ❌ | ❌ | ❌ | ⚠️ | ✅ |
| Manage collaborators | ❌ | ❌ | ❌ | ❌ | ✅ |
| Delete repository | ❌ | ❌ | ❌ | ❌ | ✅ |
| Bypass branch protection | ❌ | ❌ | ❌ | ❌ | ⚠️** |

\* If allowed by branch protection rules  
\** Only if `enforce_admins` is disabled

## Team Permissions

Teams can have the same permission levels as individual collaborators:

- **pull** (Read)
- **triage** (Triage)
- **push** (Write)
- **maintain** (Maintain)
- **admin** (Admin)

## Special Roles

### Repository Owner

- Always has full access
- Cannot be removed
- Can transfer/delete repository
- Not affected by `enforce_admins` for repository management

### Organization Owner

- Full access to all organization repositories
- Can manage organization settings
- Can manage all repositories in the organization

## Branch Protection and Roles

### With `enforce_admins` enabled

- **All roles** (including Admin) must follow protection rules
- No one can push directly to protected branches
- Everyone needs PRs and approvals

### With `enforce_admins` disabled

- **Admin and Maintain** roles can bypass protection
- **Write** and below must follow protection rules
- Admins can push directly, force push, etc.

## Best Practices

1. **Principle of Least Privilege**: Give users the minimum permission they need
2. **Use Teams**: Group users with similar access needs into teams
3. **Review Access Regularly**: Periodically review who has what access
4. **Document Access**: Keep track of why someone has a certain role
5. **Use CODEOWNERS**: Define code owners for automatic PR assignment

## Viewing Roles

You can view repository roles using:

```bash
# Using GitHub CLI
gh api repos/owner/repo/collaborators | jq '.[] | "\(.login): \(.role_name)"'

# Using the branch-protect script
./scripts/branch-protect.sh --show owner/repo
```

## References

- [GitHub Repository Permission Levels](https://docs.github.com/en/organizations/managing-access-to-your-organizations-repositories/repository-permission-levels-for-an-organization)
- [GitHub Team Permissions](https://docs.github.com/en/organizations/organizing-members-into-teams/about-teams)
- [Branch Protection and Roles](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
