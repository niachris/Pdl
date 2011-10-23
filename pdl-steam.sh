#!/bin/sh
# pdl-steam.sh (0.59)
# Copyright (c) 2008-2011 byteframe@primarydataloop

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>

function backup_database()
{
  rm -f hlstatsx/20*_backup.sql
  echo "backing up hlstatsx database..."
  mysqldump -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} \
    > hlstatsx/$(date +%Y%m%d)_backup.sql
  chmod 400 hlstatsx/$(date +%Y%m%d)_backup.sql
}

function steam_start()
{
  # startup checks
  for DEP in screen mysql wget; do
    if ! which ${DEP} > /dev/null 2>&1; then
      echo "${DEP} not installed"
      exit 1
    fi
  done
  if [ ! -w "${DIR}" ]; then
    echo "fatal: ${DIR} is not writable"
    exit 1
  elif [ -e pdl-steam.pid ]; then
    echo "error: pdl-steam is already running"
    exit 1
  fi
  source ./pdl-steam.conf || exit 1
  chmod 600 pdl-steam.conf
  touch pdl-steam.pid
  mkdir -p configs hlstatsx plugins
  chmod 700 configs
  if [ ! -e configs/autoexec.cfg ]; then
    echo -e "// autoexec.cfg\n" > configs/autoexec.cfg
  fi
  if [ ! -e configs/bans.cfg ]; then
    echo -e "// bans.cfg\n" > configs/bans.cfg
  fi

  HLX=1.6.14
  if [ ! -e hlstatsx/HLXCommunityEdition${HLX}FULL.zip ]; then
    # install/update hlstatsx
    if [ -e hlstatsx/HLXCommunityEdition*FULL.zip ]; then
      OLD_HLX=yes
    fi
    rm -fr hlstatsx/*
    wget hlstatsxcommunity.googlecode.com/files/HLXCommunityEdition${HLX}FULL.zip \
      -O hlstatsx/HLXCommunityEdition${HLX}FULL.zip || exit 1
    unzip -q hlstatsx/HLXCommunityEdition${HLX}FULL.zip -d hlstatsx
    cp hlstatsx/sourcemod/plugins/hlstatsx.smx plugins
    chmod 444 hlstatsx/HLXCommunityEdition${HLX}FULL.zip

    # configure hlstatsx
    sed -i -e "s/^DBHost \"\"/DBHost \"${DB_HOST}\"/" \
      -e "s/^DBUsername \"\"/DBUsername \"${DB_USER}\"/" \
      -e "s/^DBPassword \"\"/DBPassword \"${DB_PASS}\"/" \
      -e "s/^DBName \"\"/DBName \"${DB_NAME}\"/" \
      hlstatsx/scripts/hlstats.conf
    chmod 600 hlstatsx/scripts/hlstats.conf
    sed -i -e "s/(\"DB_ADDR\", \"localhost\");/(\"DB_ADDR\", \"\");/" \
      -e "s/(\"DB_ADDR\", \"\");/(\"DB_ADDR\", \"${DB_HOST}\");/" \
      -e "s/(\"DB_NAME\", \"\");/(\"DB_NAME\", \"${DB_NAME}\");/" \
      -e "s/(\"DB_USER\", \"\");/(\"DB_USER\", \"${DB_USER}\");/" \
      -e "s/(\"DB_PASS\", \"\");/(\"DB_PASS\", \"${DB_PASS}\");/" \
      hlstatsx/web/config.php
    chmod 660 hlstatsx/web/config.php
    sed -i -e "s/DBHOST=\"localhost\"/DBHOST=\"\"/" \
      -e "s/DBHOST=\"\"/DBHOST=\"${DB_HOST}\"/" \
      -e "s/DBNAME=\"\"/DBNAME=\"${DB_NAME}\"/" \
      -e "s/DBUSER=\"\"/DBUSER=\"${DB_USER}\"/" \
      -e "s/DBPASS=\"\"/DBPASS=\"${DB_PASS}\"/" \
      hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
    sed -i -e "s/\$( date +%m )/0\$((\`date +%m|sed \"s\/^0\/\/\"\`-1))/" \
      hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
    chmod 700 hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh

    # create/update hlstatsx database
    if [ -z ${OLD_HLX} ]; then
      echo "INPUT MYSQL ROOT PASSWORD:"
      read -s MYSQL_PASS
      mysql -h ${DB_HOST} -u root -p${MYSQL_PASS} \
        -e "CREATE DATABASE ${DB_NAME}"
      mysql -h ${DB_HOST} -u root -p${MYSQL_PASS} ${DB_NAME} \
        < hlstatsx/sql/install.sql
      mysql -h ${DB_HOST} -u root -p${MYSQL_PASS} -e \
        "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}'"
      unset MYSQL_PASS
      backup_database
      rm -fr hlstatsx/web/updater
      sh hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
      echo "DO THE FOLLOWING MANUALLY AND HIT [ENTER]"
      echo "(root) ln -s ${DIR}/hlstatsx/web /var/www/htdocs/hlstatsx"
      echo "(root) chown -R ${USER}:apache ${DIR}/hlstatsx/web"
      echo "(web) change admin pw from the default \"123456\""
      echo "(web) set to geoip lookup via database"
      read PAUSE
    else
      backup_database
      echo "UPDATE DB AT 'http://<webserver>/hlstatsx/updater' AND HIT [ENTER]"
      read PAUSE
      rm -fr hlstatsx/web/updater
    fi

    # add/update hlstatsx awards crontab entry
    if [ -z "$(crontab -l)" ]; then
      echo hlstat | crontab -
    fi
    crontab -l | sed -e \
      's!.*hlstat.*!00 00 * * * cd '${DIR}'/hlstatsx/scripts \&\& ./hlstats-awards.pl!' \
      | crontab -
  fi

  # backup hlstatsx database weekly
  if [ ! -z $(find hlstatsx -name 20*_backup.sql -mtime +7) ]; then
    backup_database
  fi

  # update hlstatsx geoip data monthy
  if [ ! -z $(find hlstatsx -name GeoLite_Import.sh -mtime +28) ]; then
    echo "upgrading hlstatsx geoip data..."
    sh hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh > /dev/null 2>&1
    touch hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
  fi

  # start hlstatsx daemon
  if [ -e hlstatsx/scripts/run_hlstats ]; then
    ( cd hlstatsx/scripts
      echo "starting hlstatsx daemon..."
      ./run_hlstats start 1> /dev/null
    )
  fi

  # install steam, and update the bootstrapper
  if [ ! -e steam ]; then
    wget -nv http://steampowered.com/download/hldsupdatetool.bin || exit 1
    chmod +x hldsupdatetool.bin
    echo yes | ./hldsupdatetool.bin
    ./steam ; ./steam
    rm -f hldsupdatetool.bin readme.txt test1.so test2.so test3.so
  fi
  ./steam -command list > /dev/null 2>&1
  STEAM_BIN="${DIR}"/steam

  # get default ip address, and initalize in-use lists
  IP=$(/sbin/ifconfig eth0 | \
    sed -n "/^[A-Za-z0-9]/ {N;/dr:/{;s/.*dr://;s/ .*//;p;}}")
  USED_NAME=,
  USED_PORT=,
  USED_HGAM=,
  USED_SGAM=,

  # process each server definition
  for ((x=0; x < ${#NAME[*]}; x++)); do
    if [ -z ${NAME[$x]} ]; then
      echo "error: empty \$NAME"
      continue
    fi
    NAME[$x]=$(echo ${NAME} | sed -e "s/ /_/g")
    if [[ ${USED_NAME} == *${NAME[$x]}* ]]; then
      echo "error: name in use, skipping: ${NAME[$x]}"
      continue
    fi
    if [ -z ${SERV[$x]} ]; then
      echo "error: missing \$SERV, skipping: ${NAME[$x]}"
      continue
    fi
    if [ -z ${PORT[$x]} ]; then
      echo "error: missing \$PORT, skipping: ${NAME[$x]}"
      continue
    fi
    if [[ ${USED_PORT} == *${PORT[$x]}* ]]; then
      echo "error: port ${PORT[$x]} in use, skipping: ${NAME[$x]}"
      continue
    fi
    if [ -z ${GAME[$x]} ]; then
      echo "error: missing \$GAME, skipping: ${NAME[$x]}"
      continue
    fi
    unset EXEC FIRST_RUN

    if [ ${SERV[$x]} = hlds ]; then
      if [[ ${USED_HGAM} == *${GAME[$x]}* ]]; then
        echo "error: a ${GAME[$x]} server is already up, skipping: ${NAME[$x]}"
        continue
      fi

      # install/update hlds game content and fix hlds_run
      GAMEDIR=hlds/${GAME[$x]}
      if [ ! -d ${GAMEDIR} ]; then
        if [ ${GAME[$x]} = cstrike ]; then
          ./steam -command update -game cstrike -dir hlds
        elif [ ${GAME[$x]} = dod ]; then
          ./steam -command update -game dod -dir hlds
        elif [ ${GAME[$x]} = tfc ]; then
          ./steam -command update -game tfc -dir hlds
        elif [ ${GAME[$x]} = valve ]; then
          ./steam -command update -game valve -dir hlds
        else
          echo "error: \"${GAME[$x]}\" not valid game for hlds"
          continue
        fi
        sed -i -e "s#\.\/steam#${STEAM_BIN}#" hlds/hlds_run
        FIRST_RUN=yes
      fi
      find ${GAMEDIR} -type l -exec rm {} \;

      # install/update metamod and amxmodx
      MM=1.19
      if [ ! -e ${GAMEDIR}/metamod-${MM}-linux.tar.gz ]; then
        rm -f ${GAMEDIR}/metamod-*-linux.tar.gz
        wget sf.net/projects/metamod/files/metamod-${MM}-linux.tar.gz \
          -O ${GAMEDIR}/metamod-${MM}-linux.tar.gz || exit 1
        mkdir -p ${GAMEDIR}/addons/metamod/dlls
        tar -xzf ${GAMEDIR}/metamod-${MM}-linux.tar.gz \
          -C ${GAMEDIR}/addons/metamod/dlls
        sed -i -e "s/\"dlls\/[a-z]*/\"addons\/metamod\/dlls\/metamod/" \
          ${GAMEDIR}/liblist.gam
      fi
      AM=1.8.1
      PCFG=${GAMEDIR}/addons/amxmodx/configs/amxx.cfg
      if [ ! -e ${GAMEDIR}/amxmodx-${AM}-base.tar.gz ]; then
        rm -f ${GAMEDIR}/amxmodx-*-*.tar.gz
        wget sf.net/projects/amxmodx/files/amxmodx-${AM}-base.tar.gz \
          -O ${GAMEDIR}/amxmodx-${AM}-base.tar.gz || exit 1
        rm -fr ${GAMEDIR}/addons/amxmodx
        tar -xzf ${GAMEDIR}/amxmodx-${AM}-base.tar.gz -C ${GAMEDIR}
        echo "linux addons/amxmodx/dlls/amxmodx_mm_i386.so" \
          > ${GAMEDIR}/addons/metamod/plugins.ini
        if [ ${GAME[$x]} != valve ]; then
          wget sf.net/projects/amxmodx/files/amxmodx-${AM}-${GAME[$x]}.tar.gz \
            -O ${GAMEDIR}/amxmodx-${AM}-${GAME[$x]}.tar.gz || exit 1
          tar -xzf ${GAMEDIR}/amxmodx-${AM}-${GAME[$x]}.tar.gz -C ${GAMEDIR}
          cp hlstatsx/amxmodx/plugins/hlstatsx_commands_${GAME[$x]}.amxx plugins
        fi
        cp ${PCFG} ${PCFG}.def
        cp ${GAMEDIR}/addons/amxmodx/configs/plugins.ini \
          ${GAMEDIR}/addons/amxmodx/configs/plugins.ini.def
        cp ${GAMEDIR}/addons/amxmodx/configs/cmds.ini \
          ${GAMEDIR}/addons/amxmodx/configs/cmds.ini.def
        cp ${GAMEDIR}/addons/amxmodx/configs/users.ini \
          ${GAMEDIR}/addons/amxmodx/configs/users.ini.def
        echo "USE THE HLSTATSX WEB GUI TO DO THE FOLLOWING AND HIT [ENTER]"
        echo "unhide game ${GAME[$x]}"
        echo "add hlds server for ${GAME[$x]}"
        read PAUSE
        ( cd hlstatsx/scripts
          echo "restarting hlstatsx daemon..."
          ./run_hlstats restart 1> /dev/null
        )
      fi

      # assemble amxmodx data
      if [ ! -e configs/${NAME[$x]}-admins.ini ]; then
        cp -v ${GAMEDIR}/addons/amxmodx/configs/users.ini.def \
          configs/${NAME[$x]}-admins.ini
      fi
      if [ ! -e configs/${NAME[$x]}-commands.ini ]; then
        cp -v ${GAMEDIR}/addons/amxmodx/configs/cmds.ini.def \
          configs/${NAME[$x]}-commands.ini
      fi
      ln -sf "${DIR}"/configs/${NAME[$x]}-admins.ini \
        ${GAMEDIR}/addons/amxmodx/configs/users.ini
      ln -sf "${DIR}"/configs/${NAME[$x]}-commands.ini \
        ${GAMEDIR}/addons/amxmodx/configs/cmds.ini
      cp ${GAMEDIR}/addons/amxmodx/configs/plugins.ini.def \
        ${GAMEDIR}/addons/amxmodx/configs/plugins.ini
      if [ ${GAME[$x]} != valve ]; then
        PLGS[$x]="hlstatsx_commands_${GAME[$x]} ${PLGS[$x]}"
      fi
      find ${GAMEDIR}/addons/amxmodx -depth -not -name compiled \
        -not -name logs -type d -empty -exec rmdir {} \;
      for FILE in ${PLGS[$x]}; do
        if [ -e plugins/${FILE}.amxx ]; then
          ln -s "${DIR}"/plugins/${FILE}.amxx ${GAMEDIR}/addons/amxmodx/plugins
          echo "${FILE}.amxx" >> ${GAMEDIR}/addons/amxmodx/configs/plugins.ini
        elif [ -d plugins/${FILE} ]; then
          lndir -silent "${DIR}"/plugins/${FILE} ${GAMEDIR}
        else
          echo "warning: plugins/${FILE}.amxx not found"
        fi
      done
      sed -i -e "s/amxx_logging\t1/amxx_logging\t0/" \
        ${GAMEDIR}/addons/amxmodx/configs/core.ini
      if [ ${DBUG[$x]} = yes ]; then
        sed -i -e "s/amxx_logging\t0/amxx_logging\t1/" \
          ${GAMEDIR}/addons/amxmodx/configs/core.ini
      fi

      # hlds configuration specifics
      BANFILE=banned.cfg
      USED_HGAM=${USED_HGAM}${GAME[$x]},
      echo "logaddress_add ${IP} 27500" > ${GAMEDIR}/server.cfg
    elif [ ${SERV[$x]} = srcds ]; then
      if [[ ${USED_SGAM} == *${GAME[$x]}* ]]; then
        echo "error: a ${GAME[$x]} server is already up, skipping: ${NAME[$x]}"
        continue
      fi

      # install srcds game content
      OB=orangebox/
      if [ ${GAME[$x]} = cstrike ]; then
        INST="Counter-Strike Source"
      elif [ ${GAME[$x]} = dod ]; then
        INST=dods
      elif [ ${GAME[$x]} = dystopia ]; then
        INST=dystopia
        unset OB
      elif [ ${GAME[$x]} = hl2mp ]; then
        INST=hl2mp
      elif [ ${GAME[$x]} = insurgency ]; then
        INST=insurgency
        unset OB
      elif [ ${GAME[$x]} = left4dead ]; then
        INST=left4dead
        OB=l4d/
      elif [ ${GAME[$x]} = left4dead2 ]; then
        INST=left4dead2
        OB=left4dead2/
      elif [ ${GAME[$x]} = tf ]; then
        INST=tf
      elif [ ${GAME[$x]} = zps ]; then
        INST=zps
      else
        echo "error: \"${GAME[$x]}\" not valid game for srcds"
        continue
      fi
      GAMEDIR=${SERV[$x]}/${OB}${GAME[$x]}
      if [ ! -d ${GAMEDIR} ]; then
        FIRST_RUN=yes
        ./steam -command update -game "${INST}" -dir srcds
        if [ ${GAME[$x]} = hl2mp ]; then
          sed -i -e "s/^hostname/\/\/hostname/" ${GAMEDIR}/cfg/valve.rc
        fi
      fi
      find ${GAMEDIR} -type l -exec rm {} \;

      # install/update sourcemod
      MS=1.8.7
      if [ ! -e ${GAMEDIR}/mmsource-${MS}-linux.tar.gz ]; then
        rm -f ${GAMEDIR}/mmsource-*-linux.tar.gz
        wget -nv sourcemod.steamfriends.com/files/mmsource-${MS}-linux.tar.gz \
          -O ${GAMEDIR}/mmsource-${MS}-linux.tar.gz || exit 1
        tar -xzf ${GAMEDIR}/mmsource-${MS}-linux.tar.gz -C ${GAMEDIR}
        wget -nv www.sourcemm.net/vdf?vdf_game=${GAME[$x]} \
          -O ${GAMEDIR}/addons/metamod.vdf || exit 1
      fi
      SM=1.3.8
      PCFG=${GAMEDIR}/cfg/sourcemod/sourcemod.cfg
      if [ ! -e ${GAMEDIR}/sourcemod-${SM}-linux.tar.gz ]; then
        rm -f ${GAMEDIR}/sourcemod-*-linux.tar.gz
        wget -nv www.n00bsalad.net/sourcemodmirror/sourcemod-${SM}-linux.tar.gz \
          -O ${GAMEDIR}/sourcemod-${SM}-linux.tar.gz || exit 1
        rm -fr ${GAMEDIR}/cfg/sourcemod ${GAMEDIR}/addons/sourcemod
        tar -xzf ${GAMEDIR}/sourcemod-${SM}-linux.tar.gz -C ${GAMEDIR}
        cp ${PCFG} ${PCFG}.def
        cp ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini \
          ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini.def
        cp ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg \
          ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg.def
        echo "(web) unhide game ${GAME[$x]}"
        echo "(web) add ${SERV[$x]} server for ${GAME[$x]}"
        read PAUSE
        ( cd hlstatsx/scripts
          echo "restarting hlstatsx daemon..."
          ./run_hlstats restart 1> /dev/null
        )
      fi

      # assemble sourcemod data
      if [ ! -e configs/${NAME[$x]}-admins.ini ]; then
        cp -v ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini.def \
          configs/${NAME[$x]}-admins.ini
      fi
      if [ ! -e configs/${NAME[$x]}-commands.ini ]; then
        cp -v ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg.def \
          configs/${NAME[$x]}-commands.ini
      fi
      ln -sf "${DIR}"/configs/${NAME[$x]}-admins.ini \
        ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini
      ln -sf "${DIR}"/configs/${NAME[$x]}-commands.ini \
        ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg
      find ${GAMEDIR}/addons/sourcemod -depth -not -name compiled \
        -not -name logs -type d -empty -exec rmdir {} \;
      for FILE in hlstatsx ${PLGS[$x]}; do
        if [ -e plugins/${FILE}.smx ]; then
          ln -sf "${DIR}"/plugins/${FILE}.smx ${GAMEDIR}/addons/sourcemod/plugins
          if [ -e plugins/${FILE}.phrases.txt ]; then
            ln -sf "${DIR}"/plugins/${FILE}.phrases.txt \
              ${GAMEDIR}/addons/sourcemod/translations
          fi
        elif [ -d plugins/${FILE} ]; then
          lndir -silent "${DIR}"/plugins/${FILE} ${GAMEDIR}
        else
          echo "warning: plugins/${FILE}.smx not found"
        fi
      done
      sed -i -e "s/Logging\"\t\t\"On\"/Logging\"\t\t\"Off\"/" \
        ${GAMEDIR}/addons/sourcemod/configs/core.cfg
      if [ ${DBUG[$x]} = yes ]; then
        sed -i -e "s/Logging\"\t\t\"Off\"/Logging\"\t\t\"On\"/" \
          ${GAMEDIR}/addons/sourcemod/configs/core.cfg
      fi

      # srcds configuration specifics
      BANFILE=banned_user.cfg
      CFGDIR=cfg
      USED_SGAM=${USED_SGAM}${GAME[$x]},
      echo "logaddress_add ${IP}:27500" > ${GAMEDIR}/${CFGDIR}/server.cfg
      if [ ! -e ${GAMEDIR}/motd_text.txt.def ]; then
        cp ${GAMEDIR}/motd_text.txt ${GAMEDIR}/motd_text.txt.def
      fi
      if [ ! -e configs/${NAME[$x]}-motd_text.txt ]; then
        cp ${GAMEDIR}/motd_text.txt.def configs/${NAME[$x]}-motd_text.txt
      fi
      ln -sf "${DIR}"/configs/${NAME[$x]}-motd_text.txt ${GAMEDIR}/motd_text.txt
    else
      echo "error: \"${SERV[$x]}\" is not a valid server type"
      continue
    fi

    # protect download tarballs for upgrade detection
    chmod 444 ${GAMEDIR}/*.tar.gz

    # assemble configuration
    ln -sf "${DIR}"/configs/autoexec.cfg ${GAMEDIR}/${CFGDIR}
    ln -sf "${DIR}"/configs/bans.cfg ${GAMEDIR}/${CFGDIR}/${BANFILE}
    {
      echo "exec ${BANFILE}"
      echo "sv_logbans 1"
      if [ ${DBUG[$x]} = yes ]; then
        echo "sv_logfile 1"
      else
        echo "sv_logfile 0"
      fi
      echo "log on"
    } >> ${GAMEDIR}/${CFGDIR}/server.cfg
    cp ${PCFG}.def ${PCFG}
    CFGS[$x]=$(echo ${CFGS[$x]} | sed -e "s/.cfg/ /g")
    for FILE in ${CFGS[$x]}; do
      if [ ${FILE} = server ]; then
        echo "warning: server.cfg is a reserved filename"
        continue;
      fi
      if [ ${FILE:0:1} = + ]; then
        FILE=${FILE:1}
        EXEC="${EXEC}+exec ${FILE}.cfg "
      elif [ ${FILE:0:1} = @ ]; then
        FILE=${FILE:1}
        echo "exec ${FILE}.cfg" >> ${GAMEDIR}/${CFGDIR}/server.cfg
      elif [ ${FILE:0:1} = % ]; then
        FILE=${FILE:1}
        echo "exec ${FILE}.cfg" >> ${PCFG}
      fi
      if [ ! -e configs/${FILE}.cfg ]; then
        echo "//" > configs/${FILE}.cfg
        echo "warning: configs/${FILE}.cfg not found; creating blank file"
      fi
      ln -s "${DIR}"/configs/${FILE}.cfg ${GAMEDIR}/${CFGDIR}
    done
    if [ ! -e ${GAMEDIR}/mapcycle.txt.def ]; then
      cp ${GAMEDIR}/mapcycle.txt ${GAMEDIR}/mapcycle.txt.def
    fi
    if [ ! -e configs/${NAME[$x]}-mapcycle.txt ]; then
      echo "warning: configs/${NAME[$x]}-mapcycle.txt not found; using default"
      cp ${GAMEDIR}/mapcycle.txt.def configs/${NAME[$x]}-mapcycle.txt
    fi
    ln -sf "${DIR}"/configs/${NAME[$x]}-mapcycle.txt ${GAMEDIR}/mapcycle.txt
    read -r STARTMAP < ${GAMEDIR}/mapcycle.txt
    if [ ! -z "${MOTD[$x]}" ]; then
      # TODO: hlds might need frameset/redirect; can't test while wine bug 6095
      echo "${MOTD[$x]}" > ${GAMEDIR}/motd.txt
    else
      echo "warning: motd url not specified; using mapcycle as greeting"
      cp ${GAMEDIR}/mapcycle.txt ${GAMEDIR}/motd.txt
    fi

    # start server
    if [ ! -z ${FIRST_RUN} ]; then
      echo "this is the first time server '${NAME[$x]}' will be started"
      echo "add/modify any configuration in 'configs' and hit [ENTER]"
      read PAUSE
    fi
    USED_NAME=${USED_NAME}${NAME[$x]},
    USED_PORT=${USED_PORT}${PORT[$x]},
    if [ ${DBUG[$x]} = yes ]; then
      if [ ${SERV[$x]} = srcds ]; then
        OPTS[$x]="-debug ${OPTS[$x]}"
      fi
    else
      rm -f ${GAMEDIR}/logs/* ${GAMEDIR}/addons/{amxmodx,sourcemod}/logs/*
    fi
    ( cd ${SERV[$x]}/${OB}
      screen -dmS steam_${NAME[$x]} ./${SERV[$x]}_run -steambin "${STEAM_BIN}" \
        -autoupdate +ip 0.0.0.0 -port ${PORT[$x]} -game ${GAME[$x]} \
        ${OPTS[$x]} ${EXEC} +sv_lan 0 +map ${STARTMAP}
    )
    echo "starting ${GAME[$x]} server ${NAME[$x]}..."
  done
}

function steam_status()
{
  screen -ls steam_
}

function steam_stop()
{
  killall -qvw hlds_run && sleep 2
  killall -qvw srcds_run && sleep 2
  if [ -e hlstatsx/scripts/run_hlstats ]; then
    ( cd hlstatsx/scripts
      ./run_hlstats stop 1> /dev/null && echo "stopped hlstatsx daemon"
    )
  fi
  rm -f pdl-steam.pid
}

DIR="$( cd "$( dirname "$0" )" && pwd )"
if [ -L "${DIR}" ]; then
  DIR=$(readlink "${DIR}")
fi
cd "${DIR}"

case ${1} in
start)
  steam_start
  ;;
status)
  steam_status
  ;;
stop)
  steam_stop
  ;;
*)
  echo "usage ${0} start|status|stop"
esac