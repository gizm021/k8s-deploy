#!/bin/bash

#*********************************#
# Author: n.andreev87@gmail.com   #
#*********************************#

ARGS=(${@}) #!#
PARAMS=(${@:2}) #!#
REPO="10.10.5.210:5000" #!#

declare -gA env_Array #!#
declare -gA secret_Data #!#
declare -gA named_Links

text_Yellow=$(echo -ne '\e[33m') #!#
text_Red=$(echo -ne '\e[31m') #!#

build_Tag=$(date +%Y%m%d%H%M%S%N) #!#
branch_Array=() #!#

service_Names=$(jq -r '.[] | keys | .[] ' /root/k8s-admin/templates/services.json)
for name in $service_Names
do
  named_Links[$name]=$(jq -r ".[] | select(.\"$name\").\"$name\".hg " /root/k8s-admin/templates/services.json)
done


__step()
{
  #-------------------------------------------------------------------------------------------#
  # __step {{STRING}}                                                                         #
  # просто красит все аргументы {{STRING}}, как строку в зелёный                              #
  # выводит строку на экран для отображения шага испольнения скрипта, где это целесообразно   #
  #-------------------------------------------------------------------------------------------#

  local string="${*}"

  echo -n "\e[32;7m" && echo -e "${string}" && tput sgr0
}

__help()
{
  #---------------------------------#
  # выводит справку через  ***      #
  #---------------------------------#
  echo -e "
  Usage:
  $(basename "${0}")    [help]
                        [list]
                        [download]  {{SERVICE_NAME}} [--to]   {{DIR_NAME}} [--up]    {{REV_NAME}}
                        [install]   {{SERVICE_NAME}} [--from] {{DIR_NAME}} [--name]  {{DEPLOY_NAME}}
  Examples:
  $(basename "${0}") download account --to \$PWD/account --up releaseBranch

  $(basename "${0}") install account --from \$PWD/account --name my-deploy-account
"  
}

__hg_download()
{
  #---------------------------------------------------------------#
  # __hg_download {{service_Name}} {{dir_Name}}                   #
  # __hg_download {{service_Name}} {{dir_Name}} {{rev_Name}}      #
  #---------------------------------------------------------------#

  case "${#@}" in
  2)
    local dest_Dir="" service_Name=${1} dir=${2} 
    URL=$(echo -e "${named_Links[${service_Name}]}") #!#

    # проверяем существует ли папка
    if [[ -d "${dir}" ]]; then
      echo -e "${text_Red} Error in __hgDownload: directory ${dir} already exit."; tput sgr0
      exit 1
    fi

    echo -e "${text_Yellow} Start download from Bitbucket"; tput sgr0
    case "${dir}" in
      '')
        hg clone "${URL}"
        dest_Dir="$(echo "${URL}" | rev | cut -d'/' -f1 | rev)" #!#
        echo  -e "\e[32;7m Folder: \e[0m \n${dest_Dir}"
      ;;
      *)
        hg clone "${URL}" "${dir}"
        echo  -e "\e[32;7m Folder: \e[0m \n${dir}"
      ;;
    esac
  ;;
  3)
    local service_Name=${1} dir=${2} rev=${3}
    URL=$(echo -e "${named_Links[${service_Name}]}") #!#

    # проверяем существует ли папка
    if [[ -d "${dir}" ]]; then
      echo -e "${text_Red} Error in __hgDownload: directory ${dir} already exit."; tput sgr0
      exit 1
    fi

    echo -e "${text_Yellow} Start download from Bitbucket"; tput sgr0
    hg clone "${URL}" "${dir}" -r "${rev}"
    if [[ $? -ne 0 ]]; then
      echo -e "${text_Red} Error in __hgDownload: ${rev} not found"; tput sgr0
    else
      echo  -e "\e[32;7m Folder: \e[0m \n${dir}"
    fi

  ;;
  esac
}

__running_list()
{
  #-------------------------------------------#
  # возвращает список имен deployment.apps    #
  #-------------------------------------------#

  local list=($(kubectl get deployments.apps -o json | jq -r '.items | .[] |  .metadata.name'))

  echo -e "${list[@]}"
}

__install_params()
{
  #-----------------------------------------------------------------------------------------------------------------#
  # разбирает {{PARAMS}}, для определения последовательности из какой {{dir_Name}} и для для какого {{deploy_Name}} #
  # надо определить одну последовательность                                                                         #
  # еще проверяет не пустые ли были параметры                                                                    #
  #-----------------------------------------------------------------------------------------------------------------#

  local option_1=${PARAMS[1]} option_2=${PARAMS[3]}
  service_Name=${PARAMS[0]} #!#
  REPO="10.10.5.210:5000" #!#

  case "${option_1}" in
    --from)
      dir_Name=${PARAMS[2]} #!#
    ;;
    --name)
      deploy_Name=${PARAMS[2]} #!#
    ;;
  esac

  case "${option_2}" in
    --from)
      dir_Name=${PARAMS[4]} #!#
    ;;
    --name)
      deploy_Name=${PARAMS[4]} #!#
    ;;
  esac

  # check params for empty
  if [[ -z "${service_Name}" ]]; then
    echo -e "${text_Red} Error in install: serviceName is empty"; tput sgr0
    exit 1
  fi

  if [[ -z "${dir_Name}" ]]; then
    echo -e "${text_Red} Error in install: dir_Name is empty"; tput sgr0
    exit 1
  fi

  if [[ -z "${deploy_Name}" ]]; then
    echo -e "${text_Yellow} Warn: deploy name undefined, will use service name"; tput sgr0
    deploy_Name=${service_Name} #!#
  fi
}

__read_service_config()
{
  #-------------------------------------#
  # надо просто переписать на глобалки  #
  #-------------------------------------#

  IMG_FPM=$(jq -r .image.fpm "${dir_Name}"/deploy/k8s/config.json) #!#
  IMG_NODE=$(jq -r .image.node "${dir_Name}"/deploy/k8s/config.json) #!#
  IMG_NGX=$(jq -r .image.nginx "${dir_Name}"/deploy/k8s/config.json) #!#
  IMG_CRON=$(jq -r .image.cron "${dir_Name}"/deploy/k8s/config.json) #!#
  IMG_SUB=$(jq -r .image.subscriber "${dir_Name}"/deploy/k8s/config.json) #!#
  IMG_WORKER=$(jq -r .image.worker "${dir_Name}"/deploy/k8s/config.json) #!#
  IMG_GEARMAN=$(jq -r .image.gearman "${dir_Name}"/deploy/k8s/config.json) #!#

  CHK_COMPOSER=$(jq -r .checks.composer "${dir_Name}"/deploy/k8s/config.json) #!#
  CHK_NODE=$(jq -r .checks.node "${dir_Name}"/deploy/k8s/config.json) #!#
  CHK_SINGLE=$(jq -r .checks.single "${dir_Name}"/deploy/k8s/config.json) #!#
  CHK_PROXY=$(jq -r .checks.proxies "${dir_Name}"/deploy/k8s/config.json) #!#
  CHK_MIGRATE=$(jq -r .checks.migrations "${dir_Name}"/deploy/k8s/config.json) #!#

  SECRET_GLOBAL=$(jq -r .secret.global "${dir_Name}"/deploy/k8s/config.json) #!#
  SECRET_LOCAL=$(jq -r .secret.local "${dir_Name}"/deploy/k8s/config.json) #!#

}

__list_deploys()
{
  #-------------------------------------------------------------#
  # __list_deploys echo                                         #
  # возвращает список deployment.apps (дубликат! надо удалить)  #
  # __list_deploys contains {{deploy_Name}}                     #
  # проверяет есть ли уже такой {{deploy_Name}}                 #
  #-------------------------------------------------------------#

  local deploy_List=($(kubectl get deployments -o json | jq -r ' .items | .[] | .metadata.name'))

  if [[ "${1}" == "echo" ]]; then
    echo -e "${deploy_List[@]}"
  elif [[ "${1}" == "contains" ]]; then
    local item=${2} list_Item="" in_List=0

    for list_Item in "${deploy_List[@]}"; do
      if [[ "${item}" == "${list_Item}" ]]; then
        in_List=$(jq -n "${in_List}"+1)
      fi
    done

  fi
  return "${in_List}"
}

__list_secrets()
{
  #---------------------------------------------------------------#
  # __list_secrets echo                                           #
  # возвращает список secrets (надо удалить)                      #
  # __list_secrets contains {{deploy_Name}}                       #
  # проверяет есть ли такой секрет, имя которого={{deploy_Name}}  #
  # 
  #---------------------------------------------------------------#

  local secret_List=($(kubectl get secrets -o json | jq -r ' .items | .[] | .metadata.name')) item=${2} list_Item="" in_List=0

  if [[ "${1}" == "echo" ]]; then
    echo -e "${secret_List[@]}"
  elif [[ "${1}" == "contains" ]]; then

    for list_Item in "${secret_List[@]}"; do
      if [[ "${item}" == "${list_Item}" ]]; then
        in_List=$(jq -n "${in_List}"+1)
      fi
    done

  fi

  # if single return 1 as True, else return in_List value
  if [[ "${CHK_SINGLE}" == "true" ]]; then
    return 1
  else
    return "${in_List}"
  fi
}

__get_secret_env()
{
  #---------------------------------------------------#
  # __get_secret_env {{deploy_Name}}                  #
  # объявляет именованый массив env_Array, в котором  #
  # key       = ENVIRONMENT_NAME                      #
  # key_value = ENVIRONMENT_VALUE (base64 decoded)    #
  #---------------------------------------------------#

  local secret_Name=${1} key=""

  if [[ -z "$secret_Name" ]]; then
    echo -e "${text_Red} Error in install: secretName undefined"; tput sgr0
    exit 1
  fi

  for key in $(kubectl get secrets "${secret_Name}" -o json | jq -r '.data | keys' | egrep -o '[A-Z_-]+'); do
    env_Array["${key}"]=$(echo -e "$(kubectl get secrets "${secret_Name}" -o json | jq -r .data[\""${key}"\"])" | base64 -d)
  done
}

__yesno_check()
{
  #-------------------------------------#
  # используется два раза... (удалить)  #
  #-------------------------------------#
  
  local ASK=""

  read -rsn1 ASK
  case "$ASK" in
    y|Y)
      return 0
    ;;
    *)
      return 1
    ;;
  esac
}

__abs_path()
{
  #-----------------------------------------------------------#
  # __abs_path {{dir_Name}}                                   #
  # возвращает полный путь до папки, полученной как параметр  #
  #-----------------------------------------------------------#
  
  local rel_Path=${1}

  echo -e "$(realpath "${rel_Path}")"
}

__composer()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить)                   #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  if [[ "${CHK_COMPOSER}" == "true" ]]; then 
    docker run \
          --rm \
          -v "$(__abs_path "${dir_Name}")":/app \
          "${REPO}"/composer \
          composer install -n -o --no-dev --ignore-platform-reqs;
  fi
}

__nodejs()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить)                   #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#
  # use: __abs_path CHK_NODE dir_Name

  if [[ "${CHK_NODE}" == "true" ]]; then
    docker  run \
            --rm \
            -ti \
            -w "/www/" \
            -v "$(__abs_path "${dir_Name}"):/www/" \
            "${REPO}/${IMG_NODE}" \
            /bin/bash -c 'npm i; npm run build; chown -R $(stat -c %u /www) /www/'
  fi

}

__k8s_conf_array()
{
  #-------------------------------#
  # (удалить) вынести в константу #
  #-------------------------------#

  conf_Array=($(ls -1 "${dir_Name}/deploy/k8s/" | egrep "^[A-Z][a-z]*\.yaml")) #!#
}

__gen_proxy()
{
  #-------------------------------------------------------#
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  local env_File="/tmp/$(date +%s%N).env" env="" #!#

  for env in "${!env_Array[@]}"; do
    echo -e "${env}=${env_Array[${env}]}" >> "${env_File}"
  done

  if [[ "${CHK_PROXY}" == 'true' ]]; then
    docker  run \
            --rm \
            -v "$(__abs_path "${dir_Name}")":/www \
            -w /www/ \
            --env-file="${env_File}" \
            "${REPO}/${IMG_FPM}" \
            /bin/bash -c "/www/vendor/doctrine/doctrine-module/bin/doctrine-module orm:generate-proxies"
  fi

  rm -rf "${env_File}"
}

__build_nginx()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить) и docker exec     #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  TAG_NGX="${REPO}/${IMG_NGX}:${build_Tag}" #!#

  docker  run \
          --rm \
          -d \
          --name "${build_Tag}" \
          "${REPO}/${IMG_NGX}"

  if [[ "$(docker ps | egrep "${build_Tag}" | wc -l)" -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_nginx: container don't start"; tput sgr0
    exit 1
  fi

  docker  exec \
          -ti \
          "${build_Tag}" \
          /bin/sh -c "mkdir -p /www/public/"

  if [[ "${CHK_SINGLE}" == "true" ]]; then
    docker  cp \
            "${dir_Name}"/. "${build_Tag}":/www/public/
  else
    docker  cp \
            "${dir_Name}"/public/. "${build_Tag}":/www/public/
  fi

  docker  commit \
          "${build_Tag}" "${TAG_NGX}"

  if [[ $(docker images | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_nginx: commit failed"; tput sgr0
    exit 1
  fi

  docker  stop \
          "${build_Tag}"

  docker  push \
          "${TAG_NGX}"

  docker  rmi \
          "${TAG_NGX}"

}

__build_fpm()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить) и docker exec     #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  TAG_FPM="${REPO}/${IMG_FPM}:${build_Tag}" #!#

  docker  run --rm -d \
          --name "${build_Tag}" \
          "${REPO}/${IMG_FPM}"

  if [[ $(docker ps | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_fpm: container don't start"; tput sgr0
    exit 1
  fi

  docker  cp \
          "${dir_Name}/." "${build_Tag}:/www"

  docker  exec \
          "${build_Tag}" \
          /bin/bash -c 'chown -R www-data:www-data /www'

  docker  commit \
          "${build_Tag}" "${TAG_FPM}"

  if [[ $(docker images | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_fpm: commit failed"; tput sgr0
    exit 1
  fi

  docker  stop \
          "${build_Tag}"

  docker  push \
          "${TAG_FPM}"

  docker  rmi \
          "${TAG_FPM}"
}

__build_nodejs()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить) и docker exec     #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  TAG_NODE="${REPO}/${IMG_NODE}:${build_Tag}" #!#

  docker  run --rm -d -ti \
          --name "${build_Tag}" \
          "${REPO}/${IMG_NODE}" \
           bash

  if [[ $(docker ps | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_nodejs: container don't start"; tput sgr0
    exit 1
  fi

  docker  cp \
          "${dir_Name}/." "${build_Tag}:/www/"

  docker  exec \
          "${build_Tag}" \
          bin/bash -c 'chown -R 33:33 /www/'

  docker  commit \
          "${build_Tag}" "${TAG_NODE}"

  if [[ $(docker images | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_fpm: commit failed"; tput sgr0
    exit 1
  fi

  docker  stop \
          "${build_Tag}"

  docker  push \
          "${TAG_NODE}"

  docker  rmi \
          "${TAG_NODE}"
}

__is_single()
{
  # use: CHK_SINGLE IMG_FPM IMG_NODE
  # assume: if IMG_FPM not exist return IMG_NODE as front || NGX_SINGLE; therway return single

  if [[ -z "${CHK_SINGLE}" ]]; then
    if [[ -n "${IMG_FPM}" ]]; then
      echo -e "fpm"
    elif [[ -n "${IMG_NODE}" ]]; then
      echo -e "nodejs"
    fi
  elif [[ "${CHK_SINGLE}" == "true" ]]; then
    echo -e "single"
  else
    echo -e "${text_Red} Error in __is_single: CHK_SINGLE IMG_FPM IMG_NODE not configured"
    exit 1
  fi
}

__build_front()
{
  # get: fpm || nodejs || single
  # use: __is_single
  
  local front=${1}

  case "${front}" in
    fpm)
      __build_fpm
    ;;
    nodejs)
      __build_nodejs
    ;;
    *)
      echo -e "\e[35;7m Pass to build nginx-single container... \e[0m"
    ;;
  esac
}

__build_subscriber()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить) и docker exec     #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  TAG_SUB="${REPO}/${IMG_SUB}:${build_Tag}" #!#

  docker  run --rm -d \
          --name "${build_Tag}" \
          "${REPO}/${IMG_SUB}"

  if [[ $(docker ps | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_subscriber: container don't start"; tput sgr0
    exit 1
  fi

  docker  cp \
          "${dir_Name}/." "${build_Tag}:/www"

  docker  exec \
          "${build_Tag}" \
          /bin/bash -c 'chown -R 33:33 /www'

  docker  commit \
          "${build_Tag}" "${TAG_SUB}"

  if [[ $(docker images | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_subscriber: commit failed"; tput sgr0
    exit 1
  fi

  docker  stop \
          "${build_Tag}"

  docker  push \
          "${TAG_SUB}"

  docker  rmi \
          "${TAG_SUB}"
}

__build_worker()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить) и docker exec     #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  TAG_WORKER="${REPO}/${IMG_WORKER}:${build_Tag}" #!#

  docker  run --rm -d \
          --name "${build_Tag}" \
          "${REPO}/${IMG_WORKER}"

  if [[ $(docker ps | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_worker: container don't start"; tput sgr0
    exit 1
  fi

  docker  cp \
          "${dir_Name}/." "${build_Tag}:/www"

  docker  exec \
          "${build_Tag}" \
          /bin/bash -c 'chown -R 33:33 /www'

  docker  commit \
          "${build_Tag}" "${TAG_WORKER}"

  if [[ $(docker images | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_worker: commit failed"; tput sgr0
    exit 1
  fi

  docker  stop \
          "${build_Tag}"

  docker  push \
          "${TAG_WORKER}"

  docker  rmi \
          "${TAG_WORKER}" 
}

__build_cron()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить) и docker exec     #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  TAG_CRON="${REPO}/${IMG_CRON}:${build_Tag}" #!#

  docker  run --rm -d \
          --name "${build_Tag}" \
          "${REPO}/${IMG_CRON}"

  if [[ $(docker ps | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_cron: container don't start"; tput sgr0
    exit 1
  fi

  docker  cp \
          "${dir_Name}/." "${build_Tag}:/www"

  docker  exec \
          "${build_Tag}" \
          /bin/bash -c 'chown -R 33:33 /www'

  docker  commit \
          "${build_Tag}" "${TAG_CRON}"

  if [[ $(docker images | egrep "${build_Tag}" | wc -l) -eq 0 ]]; then
    echo -e "${text_Red} Error in __build_cron: commit failed"; tput sgr0
    exit 1
  fi

  docker  stop \
          "${build_Tag}"

  docker  push \
          "${TAG_CRON}"

  docker  rmi \
          "${TAG_CRON}"
}

__build_gearman()
{
  # set: TAG_GEARMAN
  # use: IMG_GEARMAN REPO build_Tag

  : 'clean shellcheck'
  if [[ -n "${IMG_GEARMAN}" ]]; then
    TAG_GEARMAN="${REPO}/${IMG_GEARMAN}:${build_Tag}" #!#
  fi
}

__create_extra()
{
  #-------------------------------------------------#
  # (удалить)                                       #
  # перебирает массив conf_Array, и если встречает  #
  # intem == string_config_name                     #
  # выполняет сборку контейнера                     #
  #-------------------------------------------------#

  local config_Name=""

  for config_Name in "${conf_Array[@]}"; do
    if [[ "$(basename "${config_Name}")" == "Subscriber.yaml" ]]; then
      __build_subscriber
    elif [[ "$(basename "${config_Name}")" == "Worker.yaml" ]]; then
      __build_worker
    elif [[ "$(basename "${config_Name}")" == "Cron.yaml" ]]; then
      __build_cron
    elif [[ "$(basename "${config_Name}")" == "Gearman.yaml" ]]; then
      __build_gearman
    fi
  done
}

__run_migrations()
{
  #-------------------------------------------------------#
  # делает docker run command (удалить)                   #
  # надо написать общую функцию для такого вида действий  #
  #-------------------------------------------------------#

  local env_File="/tmp/$(date +%s%N).env" env="" #!#

  for env in "${!env_Array[@]}"; do
    echo -e "${env}=${env_Array[${env}]}" >> "${env_File}"
  done

  if [[ "${CHK_MIGRATE}" == 'true' ]]; then
    docker  run --rm \
            --name "${build_Tag}" \
            -v "$(__abs_path "${dir_Name}")":/www \
            -w /www/ \
            --env-file "${env_File}" \
            "${REPO}/${IMG_FPM}" \
            /bin/bash -c "/www/vendor/doctrine/doctrine-module/bin/doctrine-module migrations:migrate"
  fi

  rm -rf "${env_File}"
}

__set_branch_array()
{
  #-----------------------------------------------#
  # __set_branch_array {{dir_Name}}               #
  # объявляет массив, со списком веток (удалить)  #
  #-----------------------------------------------#

  local old_Path="$(pwd)" path=${1}

  cd "$(__abs_path "${path}")" || :
  branch_Array=($(hg branches | head -1)) 
  cd "${old_Path}" || :
}

__apply ()
{
  # set: ROLLOUT
  # get: config_Name from conf_Array
  # use: __set_branch_array __abs_path service_Name dir_Name build_Tag TAG_NGX TAG_FPM TAG_NODE TAG_SUB TAG_WORKER TAG_CRON TAG_GEARMAN

  local config_Name=${1}

  __set_branch_array "${dir_Name}"
  ROLLOUT="DATE=$(date +%Y-%m-%d:%H~%M:%S)_BRANCH=${branch_Array[0]}_COMMIT=${branch_Array[1]}_TAG=${build_Tag}" #!#

  case "${config_Name}" in
    Front.yaml)
      echo -e "\e[33;7m Apply: ${config_Name} \e[0m"
      if [[ "${CHK_SINGLE}" == "true" ]]; then
        sed "s|SVC|${deploy_Name}|g; s|NGX|${TAG_NGX}|g;" "${dir_Name}/deploy/k8s/${config_Name}" | kubectl apply -f -
        kubectl annotate deployments "${deploy_Name}" kubernetes.io/change-cause="${ROLLOUT}"
      elif [[ -z "${IMG_FPM}" ]]; then
        sed "s|SVC|${deploy_Name}|g; s|NGX|${TAG_NGX}|g; s|TAG|${TAG_NODE}|g;" "${dir_Name}/deploy/k8s/${config_Name}" | kubectl apply -f -
        kubectl annotate deployments "${deploy_Name}" kubernetes.io/change-cause="${ROLLOUT}"
      else
        sed "s|SVC|${deploy_Name}|g; s|NGX|${TAG_NGX}|g; s|TAG|${TAG_FPM}|g;" "${dir_Name}/deploy/k8s/${config_Name}" | kubectl apply -f -
        kubectl annotate deployments "${deploy_Name}" kubernetes.io/change-cause="${ROLLOUT}"
      fi
    ;;
    Subscriber.yaml)
      echo -e "\e[33;7m Apply: ${config_Name} \e[0m"
      sed "s|SVC|${deploy_Name}|g; s|TAG|${TAG_SUB}|g;" "${dir_Name}/deploy/k8s/${config_Name}" | kubectl apply -f -
      kubectl annotate deployments "${deploy_Name}" kubernetes.io/change-cause="${ROLLOUT}"
    ;;
    Worker.yaml)
      echo -e "\e[33;7m Apply: ${config_Name} \e[0m"
      sed "s|SVC|${deploy_Name}|g; s|TAG|${TAG_WORKER}|g;" "${dir_Name}/deploy/k8s/${config_Name}" | kubectl apply -f -
      kubectl annotate deployments "${deploy_Name}" kubernetes.io/change-cause="${ROLLOUT}"
    ;;
    Cron.yaml)
      echo -e "\e[33;7m Apply: ${config_Name} \e[0m"
      sed "s|SVC|${deploy_Name}|g; s|TAG|${TAG_CRON}|g;" "${dir_Name}/deploy/k8s/${config_Name}" | kubectl apply -f -
      kubectl annotate deployments "${deploy_Name}" kubernetes.io/change-cause="${ROLLOUT}"
    ;;
    Gearman.yaml)
      echo -e "\e[33;7m Apply: ${config_Name} \e[0m"
      sed "s|SVC|${deploy_Name}|g; s|TAG|${TAG_GEARMAN}|g;" "${dir_Name}/deploy/k8s/${config_Name}" | kubectl apply -f -
      kubectl annotate deployments "${deploy_Name}" kubernetes.io/change-cause="${ROLLOUT}"
    ;;
    *)
      echo -e "${text_Red} Error in __apply: wrong config name: ${config_Name}"; tput sgr0
      exit 1
    ;;
  esac
}

__expose()
{
  # use: deploy_Name __yesno_check

  local service_Name="${deploy_Name}" ASK="" port="" port_List=($(kubectl get svc -o wide | egrep -v '^NAME' | awk '{print $5}' | egrep -o '[0-9]+')) exist="" try=""

  echo -e "${text_Yellow} Need to expose this deployment? [y/N]"; tput sgr0
  __yesno_check
  if [[ $? -eq 0 ]]; then
    echo -e "Enter port number: "
    read -r port
    # check ${port} contains only digits
    try=$([[ "${port}" =~ ^[0-9]+$ ]]; echo $?) #!#
    while [[ ${try} -ne 0 ]]; do
      echo -e "${text_Red} Invalid value, must be a digit. $(tput sgr0) \n${text_Yellow} Try again: "; tput sgr0
      read -r port
      try=$([[ "${port}" =~ ^[0-9]+$ ]]; echo $?)
    done

    # check ${port} in use -> abort if true =(
    for exist in "${port_List[@]}"; do
      if [[ "${port}" -eq "${exist}" ]]; then
        echo -e "${text_Red} Error in __expose: ${port} already in use. Abort."; tput sgr0
        exit 1
      fi
    done

    # expose at k8s-Mater internal IP
    kubectl expose deployment "${deploy_Name}" --port="${port}" --target-port=80 --external-ip="10.10.5.211"
  fi
}

###### main ######

case ${ARGS[0]} in
  list)
    :
  ;;
  download)
    # set service_Name dir_Name
    # use: PARAMS hg_download echo_help

    if [[ ${#PARAMS[@]} -lt 1 ]]; then
      echo -e "${text_Red} Error in download: serviceName not specified"; tput sgr0
      exit 1
    fi

    if [[ ${#PARAMS[@]} -lt 3 ]]; then
      __help
      #echo -e "${text_Red} Error in download: serviceName not specified"; tput sgr0
      exit 1
    fi

    if [[ ${#PARAMS[@]} -eq 3 ]] && [[ ${PARAMS[1]} == "--up" ]]; then
      echo -e "${text_Red} Error in download: can't use [--up] without [--to] "; tput sgr0
      exit 1
    elif [[ ${#PARAMS[@]} -eq 3 ]] && [[ ${PARAMS[1]} == "--to" ]]; then
      service_Name=${PARAMS[0]} #!#
      dir_Name=${PARAMS[2]} #!#

      __hg_download "${service_Name}" "${dir_Name}"
    fi

    if [[ ${#PARAMS[@]} -eq 5 ]] && [[ ${PARAMS[1]} == "--up" ]]; then
      echo -e "${text_Red} Error in download: use [--to] first "; tput sgr0
      exit 1
    elif [[ ${#PARAMS[@]} -eq 5 ]] && [[ ${PARAMS[1]} == "--to" ]]; then
      service_Name=${PARAMS[0]} #!#
      dir_Name=${PARAMS[2]} #!#
      rev_Name=${PARAMS[4]} #!#

      __hg_download "${service_Name}" "${dir_Name}" "${rev_Name}"
    fi

  ;;
  install)
    __step "read install params"
    __install_params;

    __step "get deploy list"
    __list_deploys contains "${deploy_Name}"

    # warn if deploy exist
    if [[ $? -ne 0 ]]; then
      echo -e "${text_Yellow} Deploy: ${deploy_Name} already exist. Update? [y/N]"; tput sgr0
      __yesno_check
      if [[ $? -eq 1 ]]; then
        exit 0
      fi
    else
      echo -e "${text_Yellow} Create new deploy: $(tput sgr0) ${deploy_Name}"
    fi

    __step "read config.json"
    __read_service_config

    __step "get secret list"
    __list_secrets contains "${deploy_Name}"

    # error in no secret
    if [[ $? -eq 0 ]]; then
      echo -e "${text_Red} Error in install: secret not exist"; tput sgr0
      exit 1
    else
      __get_secret_env "${deploy_Name}"
    fi

    __step "install composer if true"
    __composer

    __step "install nodejs if true"
    __nodejs

    __step "generate proxy if true"
    __gen_proxy

    __step "get array of service configs"
    __k8s_conf_array

    __step "build nginx container"
    __build_nginx

    __step "build front containers"
    __build_front "$(__is_single)"

    __step "build extra containers"
    __create_extra
      # if Subscriber.yaml in conf_Array, create subscriber container
      # if Worker.yaml in conf_Array, create worker container
      # if Cron.yaml in conf_Array, create cron container

    __step "run migrations if true"
    __run_migrations

    __step "kubectl apply in loop"

    for a_ID in "${!conf_Array[@]}"; do
      __apply "${conf_Array["${a_ID}"]}"
    done

    __step "ask for expose"
    __expose

    __step "finish"
    exit 0
  ;;
  *)
    # любое обращение - вывод справки, выход
    __help
    exit 0
  ;;
esac
exit 0
