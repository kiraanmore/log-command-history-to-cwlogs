#!/bin/bash
AWS_INSTANCEID="`curl -k -s http://169.254.169.254/latest/meta-data/instance-id`"
AWS_REGION="`curl -k -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[abcd]$//g'`"

function getTagsByInstanceId() {
  TagName=`aws ec2 describe-tags --filters Name=resource-id,Values=${AWS_INSTANCEID} Name=key,Values=Name --query Tags[].Value --output text --region ${AWS_REGION}`
}

function DeteleKeyAndAddKeyIntoFile() {
  Key=${1}
  checkStringExists=`grep "^${Key}" ${3} | wc -l`
  echo "${checkStringExists}"
  regex="-IG[[:digit:]]"
  if [[ ${Key} =~ $regex ]]; then
    Key=${Key//$regex/}
  fi
  if (( ${checkStringExists} > 0 ));then
    sed -i "/^${Key}.*/d" ${3}
  fi
  if [[ ! -f ${3}  ]]; then
    touch ${3}
  fi
  echo "${Key}${2}" >> ${3}
}

  if [[ ! -d /var/log/conf_file ]]; then
     mkdir -p /var/log/conf_file
  fi
  declare -A alias_export_dicts
  filename="/etc/bash.bashrc"
  rsyslog_file="/etc/rsyslog.d/bash.conf"
  awslogs_python_script="/var/log/conf_file/awslogs-agent-setup.py"
  awslogs_proxyconfig_file="/var/awslogs/etc/proxy.conf"
  alias_export_dicts=([export-PROMPT_COMMAND]='$(logger -p local6.notice "User $USER has logged in")' [session_log_command()]=' { local status=$?;local command;command=$(history -a >(tee -a $HISTFILE));if [[ -n "$command" ]]; then logger -p local6.notice "Logged-in usr $USER [$$]: Executing command: $command"; history -c; history -r;fi }' [export-PROMPT_COMMAND-IG1]='session_log_command'
  [alias-exit]="'export PROMPT_COMMAND=\$(logger -p local6.notice \"User $USER has logged out\") && exit'" [alias-logout]="'export PROMPT_COMMAND=\$(logger -p local6.notice \"User $USER has logged out\") && exit'"  )
  for alias_export_vars in ${!alias_export_dicts[@]}; do
    IFS='-' read keyTag keyValue <<< ${alias_export_vars}
    if [[ -n  "${keyTag}" && -n "${keyValue}" ]]; then
        DeteleKeyAndAddKeyIntoFile "${keyTag} ${keyValue}=" "${alias_export_dicts[$alias_export_vars]}" "${filename}"
    else
      DeteleKeyAndAddKeyIntoFile "${alias_export_vars}" "${alias_export_dicts[$alias_export_vars]}" "${filename}"
    fi
  done
  source "/etc/bash.bashrc"
  if [[ ! -f ${rsyslog_file} ]]; then
    touch ${rsyslog_file}
  fi
  DeteleKeyAndAddKeyIntoFile "local6.*" " /var/log/commands.log" "${rsyslog_file}"
  DeteleKeyAndAddKeyIntoFile "&" " ~" "${rsyslog_file}"
  service rsyslog restart
  if [[ ! -f /var/log/commands.log ]]; then
  touch /var/log/commands.log
  chown syslog.adm /var/log/commands.log
  fi
  sed -i '/commands.log/d' /etc/logrotate.d/rsyslog
  sed -i '1 i/var/log/commands.log' /etc/logrotate.d/rsyslog
  if [[ ! -d /home/ubuntu/aws_scripts ]]; then
   mkdir -p /home/ubuntu/aws_scripts
  fi
  cd /home/ubuntu/aws_scripts/
  curl https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
  cp /home/ubuntu/aws_scripts/awslogs-agent-setup.py /var/log/conf_file/
  getTagsByInstanceId
  if [[ -n ${TagName} ]]; then
  echo -e "[general]
state_file = /var/awslogs/state/agent-state
[/var/log/messages]
file = /var/log/commands.log
log_group_name = /var/log/${TagName}
log_stream_name = ${AWS_INSTANCEID}
datetime_format = %b %d %H:%M:%S" > /var/log/conf_file/configuration_${AWS_INSTANCEID}
  else
    echo "TagName does not exist"
    exit 1
  fi
  sleep 5
    if [[ ! -d /var/awslogs/etc ]]; then
      mkdir -p  /var/awslogs/etc
    fi
  if [[ -f ${awslogs_python_script} ]]; then
    chmod a+x ${awslogs_python_script}
  else
        echo "aws log python script does not exist on ${awslogs_python_script} location"
        exit 1
  fi
  service awslogs restart
  echo "Restarted service awslogs"
  cd /var/log/conf_file
  chmod +x ./awslogs-agent-setup.py
  if [[ ! -f /var/log/agentlog.txt ]]; then
    touch /var/log/agentlog.txt
  fi
  /usr/bin/python ${awslogs_python_script} -n -r $AWS_REGION -c /var/log/conf_file/configuration_${AWS_INSTANCEID} | tee /var/log/agentlog.txt 2>&1
  sleep 2
  service awslogs restart
