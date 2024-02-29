#!/bin/bash
### Information
## Execution
# ./gitlab-report.sh [force]
# when force parameter is given the export will be written into ignored git file because of variable content
#
## Meaning of messages
# the messages are structured into stages with many ------ they display the stage of the project and underlying variables as example

### VARIABLES - GLOBAL
export_csv_header="ID,ELEMENT,ELEMENT-NAME,OBJECT-TYPE,OBJECT-NAME,DETAILS,COMMENT,CUSTOM-FIELD,LINK"
export_file="gitlab-report.csv"
gitlab_access_token="${GITLAB_ACCESS_TOKEN}"
gitlab_api_base="${GITLAB_API_BASE}"
gitlab_api_base_parameter="?per_page=10000"
array_of_main_groups=("7")
execution_parameter=$1
max_date_diff_alert=17
date_today="$(date +%Y-%m-%d)"
mail_content_file="mail.content"

### PRE-TASKS 
#create empty files
rm -rf $mail_content_file 

## set variables if script was executed with parameter force 
if [ "$execution_parameter" == "force" ]; then
        force=true
        # set export file name with ignorable name for git
        export_file=".ignore_gitlab-report.csv"
else
        force=false
fi

### FUNCTIONS
## calculates the days between 2 dates 
get_date_diff () {
        local expire_date=$1
        #echo $(( ($(date --date="2023-07-24" +%s) - $(date --date="2023-08-01" +%s) )/(60*60*24) ))
        let DIFF=($(date +%s -d "$expire_date")-$(date +%s -d "$date_today"))/86400
        echo $DIFF
}

## create an email template with required information to notify the team
token_expire_alert_mail () {
        local token_name=$1
        local type=$2
        local type_name=$3
        local days_left=$4
        local source_link=$5
        echo -e "TOKEN_NAME: '$token_name'\nTYPE: '$type'\nTYPE_NAME: '$type_name'\nEXPIRES_IN: '$days_left days'\nPATH: '$source_link'\n" >> $mail_content_file
}

## Check for used user token itself
check_user_tokens () {
        element="USER"
        get_personal_access_tokens=$(curl -ks --location --request GET "$gitlab_api_base/personal_access_tokens$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        readarray -t get_personal_access_tokens < <(echo "${get_personal_access_tokens}" | jq -rc '.[]') 
        if [ "$get_personal_access_tokens" == "" ]; then
                echo "USER access_token not found"
        else
                for access_token in "${get_personal_access_tokens[@]}"; do
                        objecttypename=$(echo "${access_token}" | jq -r ' .name')
                        objecttype="access_token"
                        objectdetails="expires: $(echo "${access_token}" | jq -r ' .expires_at')"
                        objectcomment="last_used: $(echo "${access_token}" | jq -r ' .last_used_at')"
                        objectcustomfield="active: $(echo "${access_token}" | jq -r ' .active')"
                        objectid="$(echo "${access_token}" | jq -r ' .id')"
                        objectname="USER-TOKEN"
                        objectlink="CHECK USER SETTINGS"
                        objectstatus="$(echo "${access_token}" | jq -r ' .active')"
                        if $objectstatus ; then
                                echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                                token_expire_date="$(echo "${access_token}" | jq -r ' .expires_at')"
                                date_diff=$(get_date_diff "$token_expire_date")
                                echo "-- $element $objecttype $objectid $objectname [expires in $date_diff days]"
                                if [ $date_diff -le $max_date_diff_alert ]; then
                                        echo "---- TRIGGER EXPIRE ALERT FOR $objectid"
                                        token_expire_alert_mail "$objecttypename" "$element" "$objectname" "$date_diff" "$objectlink"
                                fi
                        else
                                echo "-- SKIPPING $element $objecttype $objectid $objectname [expires in $date_diff days] $objectcustomfield"
                        fi
                done
        fi
}


## searches for subgroups in a group and response them
search_subgroups () {
        local id=$1
        subgroups=$(curl -ks --location --request GET "$gitlab_api_base/groups/$id/subgroups$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        echo "$subgroups"
}

## searches for projects in a group and response them
search_projects () {
        local id=$1
        projects=$(curl -ks --location --request GET "$gitlab_api_base/groups/$id/projects$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        echo "$projects"
}

## searches for available runners for used user and response them
search_runners () {
        local id=$1
        runners=$(curl -ks --location --request GET "$gitlab_api_base/runners$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        echo "$runners"
}

## export information of a project
report_project () {
        # set some variables and arrays including getting information from api
        local id=$1
        element="project"
        get_object_variables=$(curl -ks --location --request GET "$gitlab_api_base/projects/$id/variables$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        get_object_access_tokens=$(curl -ks --location --request GET "$gitlab_api_base/projects/$id/access_tokens$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        get_object_info=$(curl -ks --location --request GET "$gitlab_api_base/projects/$id" --header "Authorization: Bearer $gitlab_access_token")
        get_object_pipeline_schedules=$(curl -ks --location --request GET "$gitlab_api_base/projects/$id/pipeline_schedules$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        get_object_branches=$(curl -ks --location --request GET "$gitlab_api_base/projects/$id/repository/branches$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        readarray -t get_object_variables < <(echo "${get_object_variables}" | jq -rc '.[]') 
        readarray -t get_object_access_tokens < <(echo "${get_object_access_tokens}" | jq -rc '.[]') 
        readarray -t get_object_pipeline_schedules < <(echo "${get_object_pipeline_schedules}" | jq -rc '.[]') 
        readarray -t get_object_branches < <(echo "${get_object_branches}" | jq -rc '.[]') 
        # conditions for project information reports
        if [ "$get_object_variables" == "" ]; then
                echo "------ project $id found NO variable"
        else
                for variable in "${get_object_variables[@]}"; do
                        objecttypename=$(echo "${variable}" | jq -r ' .key')
                        objecttype="variable"
                        objectdetails=""
                        objectcomment=""
                        objectcustomfield=""
                        objectid=$(echo "${get_object_info}" | jq -r ' .id')
                        objectname=$(echo "${get_object_info}" | jq -r ' .name')
                        objectlink=$(echo "${get_object_info}" | jq -r ' .web_url')
                        # condition to export in an ignored file the variable content
                        if [ "$force" == "true" ]; then
                                objectdetails=$(echo "${variable}" | jq -r ' .value')
                                echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                        else
                                echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                        fi
                        echo "------ $element $id found $objecttype $objecttypename"
                done
        fi
        if [ "$get_object_access_tokens" == "" ]; then
                echo "------ project $id found NO access_token"
        else
                for access_token in "${get_object_access_tokens[@]}"; do
                        objecttypename=$(echo "${access_token}" | jq -r ' .name')
                        objecttype="access_token"
                        objectdetails="expires: $(echo "${access_token}" | jq -r ' .expires_at')"
                        objectcomment="last_used: $(echo "${access_token}" | jq -r ' .last_used_at')"
                        objectcustomfield="active: $(echo "${access_token}" | jq -r ' .active')"
                        objectid=$(echo "${get_object_info}" | jq -r ' .id')
                        objectname=$(echo "${get_object_info}" | jq -r ' .name')
                        objectlink=$(echo "${get_object_info}" | jq -r ' .web_url')
                        objectstatus="$(echo "${access_token}" | jq -r ' .active')"
                        if $objectstatus ; then
                                echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                                token_expire_date="$(echo "${access_token}" | jq -r ' .expires_at')"
                                date_diff=$(get_date_diff "$token_expire_date")
                                echo "------ $element $objecttype $objectid $objectname [expires in $date_diff days]"
                                if [ $date_diff -le $max_date_diff_alert ]; then
                                        echo "---- TRIGGER EXPIRE ALERT FOR $objectid"
                                        token_expire_alert_mail "$objecttypename" "$element" "$objectname" "$date_diff" "$objectlink"
                                fi
                        else
                                echo "------ SKIPPING $element $objecttype $objectid $objectname [expires in $date_diff days] $objectcustomfield"
                        fi
                done
        fi
        if [ "$get_object_pipeline_schedules" == "" ]; then
                echo "------ project $id found NO pipeline_schedule"
        else
                for pipeline_schedule in "${get_object_pipeline_schedules[@]}"; do
                        objecttypename=$(echo "${pipeline_schedule}" | jq -r ' .description')
                        objecttype="pipeline_schedule"
                        objectdetails="active: $(echo "${pipeline_schedule}" | jq -r ' .active')"
                        objectcomment="cron: $(echo "${pipeline_schedule}" | jq -r ' .cron')"
                        objectcustomfield="schedule_id: $(echo "${pipeline_schedule}" | jq -r ' .id')"
                        objectid=$(echo "${get_object_info}" | jq -r ' .id')
                        objectname=$(echo "${get_object_info}" | jq -r ' .name')
                        objectlink=$(echo "${get_object_info}" | jq -r ' .web_url')
                        echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                        echo "------ $element $id found $objecttype $objecttypename"
                done
        fi
        if [ "$get_object_branches" == "" ]; then
                echo "------ project $id ERROR in branches"
        else
                for branch in "${get_object_branches[@]}"; do
                        objecttypename="$(echo "${branch}" | jq -r ' .name')"
                        objecttype="branch"
                        objectdetails="last-commit: $(echo "${branch}" | jq -r ' .commit.created_at')"
                        objectcomment=""
                        objectcustomfield=""
                        objectid=$(echo "${get_object_info}" | jq -r ' .id')
                        objectname=$(echo "${get_object_info}" | jq -r ' .name')
                        objectlink=$(echo "${get_object_info}" | jq -r ' .web_url')
                        # CHECK IF BRANCH HAS A .gitlab-ci.yml FILE
                        get_branch_cicd_file_information=$(curl -ks --location --request GET "$gitlab_api_base/projects/$id/repository/files/.gitlab-ci.yml/blame?ref=$objecttypename" --header "Authorization: Bearer $gitlab_access_token")
                        if [[ "$get_branch_cicd_file_information" == *"commit"* ]]; then
                                objectcomment=".gitlab-ci.yml exist"
                        else
                                objectcomment="no .gitlab-ci.yml found"
                        fi
                        echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                        echo "------ $element $id found $objecttype $objecttypename with $objectcomment"
                done
        fi

}

## export information of a (sub)group
report_subgroup () {
        # set some variables and arrays including getting information from api
        local id=$1
        element="subgroup"
        get_object_variables=$(curl -ks --location --request GET "$gitlab_api_base/groups/$id/variables$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        get_object_info=$(curl -ks --location --request GET "$gitlab_api_base/groups/$id/" --header "Authorization: Bearer $gitlab_access_token")
        get_object_access_tokens=$(curl -ks --location --request GET "$gitlab_api_base/groups/$id/access_tokens$gitlab_api_base_parameter" --header "Authorization: Bearer $gitlab_access_token")
        readarray -t get_object_access_tokens < <(echo "${get_object_access_tokens}" | jq -rc '.[]') 
        readarray -t get_object_variables < <(echo "${get_object_variables}" | jq -rc '.[]' )

        # conditions for (sub)group information reports
        if [ "$get_object_variables" == "" ]; then
                echo "------ subgroup $id found NO variable"
        else
                for variable in "${get_object_variables[@]}"; do
                        objecttypename=$(echo "${variable}" | jq -r ' .key')
                        objecttype="variable"
                        objectdetails=""
                        objectcomment=""
                        objectcustomfield=""
                        objectid=$(echo "${get_object_info}" | jq -r ' .id')
                        objectname=$(echo "${get_object_info}" | jq -r ' .name')
                        objectlink=$(echo "${get_object_info}" | jq -r ' .web_url')
                        # condition to export in an ignored file the variable content
                        if [ "$force" == "true" ]; then
                                objectdetails=$(echo "${variable}" | jq -r ' .value')
                                echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                        else
                                echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                        fi
                        echo "------ $element $id found $objecttype $objecttypename"

                done
        fi
        if [ "$get_object_access_tokens" == "" ]; then
                echo "------ subgroup $id found NO access_token"
        else
                for access_token in "${get_object_access_tokens[@]}"; do
                        objecttypename=$(echo "${access_token}" | jq -r ' .name')
                        objecttype="access_token"
                        objectdetails="expires: $(echo "${access_token}" | jq -r ' .expires_at')"
                        objectcomment="last_used: $(echo "${access_token}" | jq -r ' .last_used_at')"
                        objectcustomfield="active: $(echo "${access_token}" | jq -r ' .active')"
                        objectid=$(echo "${get_object_info}" | jq -r ' .id')
                        objectname=$(echo "${get_object_info}" | jq -r ' .name')
                        objectlink=$(echo "${get_object_info}" | jq -r ' .web_url')
                        objectstatus="$(echo "${access_token}" | jq -r ' .active')"
                        if $objectstatus ; then
                                echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
                                token_expire_date="$(echo "${access_token}" | jq -r ' .expires_at')"
                                date_diff=$(get_date_diff "$token_expire_date")
                                echo "------ $element $objecttype $objectid $objectname [expires in $date_diff days]"
                                if [ $date_diff -le $max_date_diff_alert ]; then
                                        echo "---- TRIGGER EXPIRE ALERT FOR $objectid"
                                        token_expire_alert_mail "$objecttypename" "$element" "$objectname" "$date_diff" "$objectlink"
                                fi
                        else
                                echo "------ SKIPPING $element $objecttype $objectid $objectname [expires in $date_diff days] $objectcustomfield"
                        fi                        
                done
        fi

}

## export information of a gitlab-runner
report_runner_details () {
        # set some variables and arrays including getting information from api
        local id=$1
        element="gitlab-runner"
        get_object_info=$(curl -ks --location --request GET "$gitlab_api_base/runners/$id/" --header "Authorization: Bearer $gitlab_access_token")

        objecttypename="$(echo "${get_object_info}" | jq -r ' .description')[$(echo "${get_object_info}" | jq -r ' .ip_address')]"
        objecttype="$(echo "${get_object_info}" | jq -r ' .platform'):v$(echo "${get_object_info}" | jq -r ' .version') defined_as:$(echo "${get_object_info}" | jq -r ' .runner_type')"
        objectcomment="last_used: $(echo "${get_object_info}" | jq -r ' .contacted_at')"
        objectcustomfield="SETTINGS=ACTIVE:$(echo "${get_object_info}" | jq -r ' .active');ONLINE:$(echo "${get_object_info}" | jq -r ' .online');STATUS:$(echo "${get_object_info}" | jq -r ' .status');PAUSED:$(echo "${get_object_info}" | jq -r ' .paused');LOCKED:$(echo "${get_object_info}" | jq -r ' .locked');SHARED:$(echo "${get_object_info}" | jq -r ' .is_shared');RUN_UNTAGGED:$(echo "${get_object_info}" | jq -r ' .run_untagged');MAX_TIMEOUT:$(echo "${get_object_info}" | jq -r ' .maximum_timeout');ACCESS_LEVEL:$(echo "${get_object_info}" | jq -r ' .access_level')"
        objectid=$(echo "${get_object_info}" | jq -r ' .id')
        objectname=$(echo "${get_object_info}" | jq -r ' .name')
        objectdetails=$(echo "${get_object_info}" | jq -r '.tag_list | join(";")')
        objectlink="used in: GROUPS[$(echo "${get_object_info}" | jq -r '.groups | map(.id) | join(";")')] PROJECTS[$(echo "${get_object_info}" | jq -r '.projects | map(.id) | join(";")')]"

        echo "$objectid,$element,$objectname,$objecttype,$objecttypename,$objectdetails,$objectcomment,$objectcustomfield,$objectlink" >> $export_file
        echo "------ $element $id found $objecttype $objecttypename"
}

## Sub-fuction of main function for reporting groups and projects
while_subgroups_exist () {
        # set some variables and arrays
        local groupid=$1
        echo "-- while_subgroups_exist_id $groupid"
        subgroups=$(search_subgroups "${groupid}")

        # makes a reverse lookup into gitlab for subgroups and calls report functions
        if [ "$subgroups" != "" ]; then
                readarray -t subgroups < <(echo "${subgroups}" | jq -rc '.[]' )

                for subgroup in "${subgroups[@]}"; do
                        subgroupid=$(echo "${subgroup}" | jq -r ' .id')
                        subgroupname=$(echo "${subgroup}" | jq -r ' .name')
                        echo "---- subgroup $subgroupname"
                        while_subgroups_exist "$subgroupid"
                done
        fi

        projects=$(search_projects "${groupid}")
        readarray -t projects < <(echo "${projects}" | jq -rc '.[]' )

        for project in "${projects[@]}"; do
                projectid=$(echo "${project}" | jq -r ' .id')
                projectname=$(echo "${project}" | jq -r ' .name')
                echo "---- project $projectname"
                report_project "$projectid"
                done

        report_subgroup "$groupid"
}

## function to get all available gitlab-runners and call report runner details funtion 
report_all_available_gitlab_runner () {
        # set some variables and arrays
        # makes a reverse lookup into gitlab for subgroups and calls report functions
        runners=$(search_runners)
        readarray -t runners < <(echo "${runners}" | jq -rc '.[]' )
                for runner in "${runners[@]}"; do
                runnerid=$(echo "${runner}" | jq -r ' .id')
                runnername=$(echo "${runner}" | jq -r ' .description')
                echo "-- report gitlab-runner $runnername"
                report_runner_details "$runnerid"
                done
}

# main function for all separated executed funcions
main_function () {
        # export header into export file
        echo "$export_csv_header" > $export_file
        
        # check for user token expiration
        check_user_tokens

        # main function part for reporting content of given main groups defined as array
        for main_group in "${array_of_main_groups[@]}"; do
                echo "Main Group Run for ID $main_group"
                while_subgroups_exist "$main_group"
        done

        # execute function to report all available gitlab-runners
        echo "Start report of all available gitlab-runners for used user"
        report_all_available_gitlab_runner
}


# execution of the main function
main_function


