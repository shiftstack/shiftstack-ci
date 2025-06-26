# Create jira bugs for backports from upstream

Create bugs for merging backports:
- run script with the URL of the PR
- check if there is an open bug for the component and release
- create new bug with
	- component "Cloud Compute / OpenStack Provider" (for CAPO and CPO - we don't sync NFS to stable branches)
	- type bug
	- prio normal
	- Affects version: target branch
	- labels: Triaged
	- description
- create a dependent bug if none already
	- search for open bugs with upper version
- tag PR with the new bug

## Usage

Install dependencies:
```
❯ pip install -r requirements.txt
```

Export both the `JIRA_TOKEN` and `GITHUB_TOKEN` environment variables with valid personal access tokens for [Jira](https://issues.redhat.com/secure/ViewProfile.jspa?selectedTab=com.atlassian.pats.pats-plugin:jira-user-personal-access-tokens) and [Github](https://github.com/settings/tokens).

Then run the script and pass it the URL of a pull request:

```
❯ python ./jira-backport.py https://github.com/openshift/cluster-api-provider-openstack/pull/346
no existing issue... will create one
created issue: OCPBUGS-58028
Retitling PR to: OCPBUGS-58028: Merge https://github.com/kubernetes-sigs/cluster-api-provider-openstack:release-0.10 into release-4.16
```
