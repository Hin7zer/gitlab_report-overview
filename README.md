# gitlab_report-overview



## Getting started

Short instruction of what the script gitlab-report.sh is doing with example executions.

This repository and script is used for creating an report of objects of an array of gitlab groups.
A local execution is possible.

### What is this script doing?

This script makes a reverse lookup inside one or more "main groups" and searches for other subgroups and their projects.

The script reports information about group and project with information at currently (2023-10-14) branches,variables and pipeline schedules.

Most of the information are only refered to the projects. Because of the reason a group can contain variables for multiple projects it is reporting them aswell

In case of some execution parameters it expands some report information but this is supposed to use only local.

## Execution examples

Create a basic report without execution parameters used for pipeline:
```
bash ./gitlab-report.sh
```

Create report with alternative information with using execution parameters:
```
bash ./gitlab-report.sh [execution_parameter]
bash ./gitlab-report.sh force
```
## execution parameters

### force
This parameter changes the export file name which will be ignored by the git ignore file and extends the report with information of variable content.
Because of secure information this should be used only local and deleted after finish.

## IMPORTANT NOTES
The delimeter in the export is a "," so the branch/variable/pipeline_schedule name/description can not have a comma in the fields.
Because of the force parameter the variable value needs to be checked manual for comma.
