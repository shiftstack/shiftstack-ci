from jira import JIRA
from github import Github
from github import Auth
import os
import re
import sys

# TODO
# - Set Target version to be the same as the affected version
# - Set Release notes not required
# - Set Assignee
# - Create parent bug if needed
# - Work on main/master and not just "release-xxx" branches


def getUpstreamBranch(repo, branch):
    y_version = branch.split("release-4.")[1]
    # OCP follows kube release cycle, but with 13 y-versions difference
    kube_y_version = int(y_version) + 13
    if repo.name == "cluster-api-provider-openstack":
        if int(y_version) == 15:
            return "release-0.8"
        elif int(y_version) <= 17:
            return "release-0.10"
        elif int(y_version) <= 18:
            return "release-0.11"
        else:
            return "release-0.12"
    else:
        return "release-1.{}".format(kube_y_version)


def getPR(url):
    m = re.match(r'.*github.com\/(?P<repo_name>[-_\w]+\/[-_\w]+)\/pull\/(?P<pr_number>\d+)', url)
    repo_name = m.group('repo_name')
    pr_number = int(m.group('pr_number'))

    repo=github.get_repo(repo_name)
    pr = repo.get_pull(pr_number)

    return pr

def findOrCreateJira(repo, branch):
    issue = findJira(repo, branch)

    if issue:
        print("found existing issue: {}".format(issue))
    else:
        print("no existing issue... will create one")
        issue = createJira(repo, branch)
        print("created issue: {}".format(issue))
    return issue


def findJira(repo, branch):
    version = branch.split("release-")[1]

    if repo.name in ["cloud-provider-openstack", "cluster-api-provider-openstack"]:
        component = "Cloud Compute / OpenStack Provider"
    else:
        return
    query = 'summary ~ "Sync stable branch for {project}" and project = "OpenShift Bugs" and component = "{component}" and affectedVersion = {version}.z and status not in (Verified, Closed)'.format(
            project = repo.name,
            component = component,
            version = version,
            )
    issues = jira.search_issues(query, maxResults=1)
    for issue in issues:
        return issue

def createJira(repo, branch):
    upstream_branch = getUpstreamBranch(repo, branch)
    summary = 'Sync stable branch for {repo} {upstream_branch} into {branch}'.format(
            branch=branch,
            upstream_branch=upstream_branch,
            repo=repo.name,
            )
    description = """Description of problem:{{code:none}}
{branch} of {repo} is missing some commits that were backported in upstream project into the {upstream_branch} branch.
We should import them in our downstream fork.
{{code}}""".format(branch=branch,
               upstream_branch=upstream_branch,
               repo=repo.full_name)
    version = branch.split("release-")[1]

    # TODO(mandre) add test coverage and target version so that the but does
    # not remove the triage label
    # also assignee
    issue_dict = {
            'project': {'key': 'OCPBUGS'},
            'summary': summary,
            'description': description,
            'issuetype': {'name': 'Bug'},
            'priority': {'name': 'Normal'},
            'components': [{'name': 'Cloud Compute / OpenStack Provider'}],
            'labels': ['Triaged'],
            'versions': [{'name': "{}.z".format(version)}],
            }
    return jira.create_issue(fields=issue_dict)

def retitlePR(pr, issue_key):
    m = re.match(r'(OCPBUGS-\d+:\s*)?(?P<title>.+)', pr.title)
    new_title = "{}: {}".format(issue_key, m.group('title'))
    if pr.title != new_title:
        print("Retitling PR to: {}".format(new_title))
        pr.create_issue_comment("/retitle {}".format(new_title))


if len(sys.argv) < 1:
    print("Pass the URL of a github PR from mergebot")
    exit()

# Get yours at
# https://issues.redhat.com/secure/ViewProfile.jspa?selectedTab=com.atlassian.pats.pats-plugin:jira-user-personal-access-tokens
jira_token = os.environ.get('JIRA_TOKEN', "")
if jira_token == "":
    print("Missing or empty JIRA_TOKEN environment variable")
    exit()

# Get yours at https://github.com/settings/tokens
gh_token = os.environ.get('GITHUB_TOKEN', "")
if gh_token == "":
    print("Missing or empty GITHUB_TOKEN environment variable")
    exit()

jira = JIRA(server="https://issues.redhat.com", token_auth=jira_token)
github = Github(auth=Auth.Token(gh_token))

url = sys.argv[1]
pr = getPR(url)

issue = findOrCreateJira(pr.base.repo, pr.base.ref)

# Retitle github PR if needed
if issue:
    retitlePR(pr, issue.key)
