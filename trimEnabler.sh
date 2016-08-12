#!/bin/bash

# Variables initialisation
version="trimEnabler v0.4 - 2016, Yvan Godard [godardyvan@gmail.com]"
SystemOS=$(sw_vers -productVersion | awk -F "." '{print $0}')
SystemOSMajor=$(sw_vers -productVersion | awk -F "." '{print $1}')
SystemOSMinor=$(sw_vers -productVersion | awk -F "." '{print $2}')
SystemOSPoint=$(sw_vers -productVersion | awk -F "." '{print $3}')
scriptDir=$(dirname "${0}")
scriptName=$(basename "${0}")
scriptNameWithoutExt=$(echo "${scriptName}" | cut -f1 -d '.')
trimNotEnabled=0
trimEnabled=0
hasOneOrMoreSSD=0
numberOfTrim=0
varDirTrimEnabler="/var/${scriptNameWithoutExt}"
varBackupDirTrimEnabler=${varDirTrimEnabler%/}/kextBackup
IOAHCIBlockStorage="/System/Library/Extensions/IOAHCIFamily.kext/Contents/PlugIns/IOAHCIBlockStorage.kext/Contents/MacOS/IOAHCIBlockStorage"
backupIncipit=$(basename ${IOAHCIBlockStorage})
backupExtension="original-$(date +%d.%m.%y@%Hh%M)"
backupFile=${varBackupDirTrimEnabler%/}/${backupIncipit}.${backupExtension}
historyKextPatches=${varDirTrimEnabler%/}/historyKextPatches.txt

function deleteTmpFiles () {
	ls /tmp/${scriptNameWithoutExt}* > /dev/null 2>&1
	[ $? -eq 0 ] && rm -R /tmp/${scriptNameWithoutExt}*
}

# Exécutable seulement par root
if [ `whoami` != 'root' ]; then
	echo "Ce script doit être utilisé par le compte root. Utilisez 'sudo'."
	exit 1
fi

echo ""
echo "****************************** `date` ******************************"
echo "${scriptName} démarré..."
echo "sur Mac OSX version ${SystemOS}"
echo ""

if [[ ! -d ${varDirTrimEnabler} ]]; then
	mkdir -p ${varDirTrimEnabler}
	if [ $? -ne 0 ]; then
		echo "> Problème rencontré pour créer le dossier '${varDirTrimEnabler}'."
		echo "> Nous quittons."
		logger \"-- [${scriptName}] : Problème rencontré pour créer le dossier '${varDirTrimEnabler}'.\"
		exit 1
	fi
fi
if [[ ! -d ${varBackupDirTrimEnabler} ]]; then
	mkdir -p ${varBackupDirTrimEnabler}
	if [ $? -ne 0 ]; then
		echo "> Problème rencontré pour créer le dossier '${varBackupDirTrimEnabler}'."
		echo "> Nous quittons."
		logger \"-- [${scriptName}] : Problème rencontré pour créer le dossier '${varBackupDirTrimEnabler}'.\"
		exit 1
	fi
fi
[[ ! -e ${historyKextPatches} ]] && touch ${historyKextPatches}

# Suppression des anciens fichiers temporaires
deleteTmpFiles

# Changement du séparateur par défaut
OLDIFS=$IFS
IFS=$'\n'
# On vérifie le statut SSD avec la commande system_profiler car avec diskutil info, 
# certains SSD patchés pour le support de TRIM ne sont plus reconnus comme SSD
for disque in $(system_profiler -detailLevel mini SPSerialATADataType | grep "Medium Type"); do
	echo "${disque}" | grep "Solid State" > /dev/null 2>&1
	[ $? -eq 0 ] && let hasOneOrMoreSSD=${hasOneOrMoreSSD}+1
done
IFS=$OLDIFS

# Rechercehde tous les SSD / ancienne méthode utilisant la fonction diskutil
# plus utilisée, car sur certains disques dont le kext a été patché pour activer trim
# l'information "Solid State" ne remonte pas
# for disk in $(diskutil list | grep "/dev/") ; do 
#	[[ $(diskutil info "$disk" | grep "Solid State" | awk -F " " '{print $3}' | grep "Yes") -eq "Yes" ]] && let hasOneOrMoreSSD=${hasOneOrMoreSSD}+1
# done

# On arrête le processus s'il n'y a pas de SSD
# [[ ${hasOneOrMoreSSD} -eq 0 ]] >> il n'y a pas de SSD
if [[ ${hasOneOrMoreSSD} -eq 0 ]] ; then
	echo "Votre système ne possède pas de Solid State Drive (SSD) ou disque Fusion Drive."
	echo "> Nous quittons donc le processus."
	exit 0
fi

# Check du TRIM Support
# [[ ${trimNotEnabled} -ne 0 ]] >> support Trim non activé
for trimSupport in $(system_profiler -detailLevel mini SPSerialATADataType | grep "TRIM Support" | awk '{print $3}') ; do
	let numberOfTrim=${numberOfTrim}+1
	[[ "${trimSupport}" == "No" ]] && let trimNotEnabled=${trimNotEnabled}+1
	[[ "${trimSupport}" == "Yes" ]] && let trimEnabled=${trimEnabled}+1
done

# Si trim support = Yes sur chaque occurence, alors TRIM est correctement activé
if [[ ${trimEnabled} -eq ${numberOfTrim} ]] ; then
	echo "Votre système possède bien un Solid State Drive (SSD) ou disque Fusion Drive,"
	echo "mais le support de TRIM est déjà activé correctement."
	echo "> Nous quittons donc le processus."
	exit 0
fi

# [[ ${trimNotEnabled} -ne 0 ]] >> support Trim non activé
if [[ ${trimNotEnabled} -eq 0 ]] ; then
	echo "Votre système possède bien un Solid State Drive (SSD) ou disque Fusion Drive,"
	echo "mais le support de TRIM ne semble pas pris en charge."
	echo "Nous ne trouvons pas 'TRIM support' dans les options du (des) disque(s)."
	echo "> Nous quittons donc le processus."
	exit 0
fi

## Si le système est OS ≥ 10.10.4
if [[ ${SystemOSMinor} -ge 11 ]] || [[ ${SystemOSMajor} -eq 10 && ${SystemOSMinor} -ge 10 && ${SystemOSPoint} -ge 4 ]] ; then
	tmpInputEnableTrim=$(mktemp /tmp/${scriptNameWithoutExt}_tmpInputEnableTrim.XXXXX)
	echo "y" > ${tmpInputEnableTrim}
	echo "y" >> ${tmpInputEnableTrim}
	trimforce enable < ${tmpInputEnableTrim}
	logger \"-- [${scriptName}] : activation de trim avec la commande 'trimforce enable'.\"
	##remove stdin input file
	rm -f ${tmpInputEnableTrim}
fi

## Si le système est entre 10.10.0 > 10.10.3
if [[ ${SystemOSMajor} -eq 10 ]] && [[ ${SystemOSMinor} -eq 10 ]] && [[ ${SystemOSPoint} -ge 0 ]] && [[ ${SystemOSPoint} -lt 4 ]] && [[ ! ( `nvram boot-args 2>/dev/null` =~ kext-dev-mode=1$ ) ]] ; then
	echo "Ce script ne fonctionne pas sur OS X Yosemite (de 10.10.0 à 10.10.4)"
	echo "sans avoir désactivé préalablement la signature des pilotes."
	logger \"-- [${scriptName}] : trimEnabler désactive Kext signing et reboote.\"
	echo "Nous désactivons Kext-signing et rebootons."
	echo "Si vous lancez ce script manuellement, vous devez le relancer"
	echo "après que l'ordinateur ait redémarré."
    nvram boot-args=kext-dev-mode=1
    deleteTmpFiles
    shutdown -r now
fi

## Si le système est OS ≥ 10.10.4
if [[ ${SystemOSMajor} -eq 10 && ${SystemOSMinor} -lt 10 ]] || [[ ${SystemOSMajor} -eq 10 && ${SystemOSMinor} -eq 10 && ${SystemOSPoint} -lt 4 ]]; then

	## Définition du dernier fichier de backup
	ls -t1 ${varBackupDirTrimEnabler%/}/${backupIncipit}.original* > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		cd ${varBackupDirTrimEnabler%/}
		lastBackupFileName=$(ls -t1 ${backupIncipit}.original* | head -1)
		cd ${scriptDir}
	else
		lastBackupFileName=""
	fi

	## Test si déjà réalisé
	if [[ ! -z ${lastBackupFileName} ]] \
		&& [[ $(md5 -q ${IOAHCIBlockStorage}) != $(md5 -q ${varBackupDirTrimEnabler%/}/${lastBackupFileName}) ]] \
		&& [[ ! -z $(cat ${historyKextPatches}) ]] \
		&& [[ $(cat ${historyKextPatches}) == $(echo ${SystemOS}) ]]; then
		echo "Le Kext a déjà été patché pour cette version de OS X ${SystemOS}."
		echo "Si vous souhaitez patcher à nouveau le Kext vous devez supprimer"
		echo "manuellement le fichier '${lastBackupFileName}'"
		echo "et relancer ce script."
		echo "> Nous quittons le processus."
		exit 0
	elif [[ -z ${lastBackupFileName} ]] \
		|| [[ ! -z ${lastBackupFileName} && $(md5 -q ${IOAHCIBlockStorage}) == $(md5 -q ${varBackupDirTrimEnabler%/}/${lastBackupFileName}) ]] \
		|| [[ ! -z $(cat ${historyKextPatches}) && $(cat ${historyKextPatches}) < $(echo ${SystemOS}) ]] \
		|| [[ -z $(cat ${historyKextPatches}) ]] ; then

		## Copie de backup du fichier kext
		cp ${IOAHCIBlockStorage} ${backupFile}
		if [ $? -ne 0 ]; then
			echo "> Problème rencontré pour copier le fichier '${IOAHCIBlockStorage}' à l'emplacement de backup '${backupFile}'."
			echo "> Nous quittons."
			logger \"-- [${scriptName}] : Problème rencontré pour copier le fichier '${IOAHCIBlockStorage}' vers '${backupFile}'.\"
			exit 1
		fi

		# Patch the file to enable TRIM support
		# This nulls out the string "APPLE SSD" so that string compares will always pass.
		# on 10.9.4 to 10.9.5 and 10.10.0-10.10.1 the sequence is WakeKey\x0a\0APPLE SSD\0Time To Ready\0
		# on 10.8.3 to 10.8.5 and 10.9.0 to 10.9.3, the sequence is Rotational\0APPLE SSD\0Time To Ready\0
		# on 10.8.1 to 10.8.2 and Lion 10.7.5, the sequence is Rotational\0APPLE SSD\0MacBook5,1\0
		# on 10.8.0 and Lion 10.7.4 BELOW, the sequence is Rotational\0\0APPLE SSD\0\0\0Queue Depth\0
		# The APPLE SSD is to be replaced with a list of nulls of equal length (9).
		perl -p0777i -e 's@((?:Rotational|WakeKey\x0a)\x00{1,20})APPLE SSD(\x00{1,20}[QMT])@$1\x00\x00\x00\x00\x00\x00\x00\x00\x00$2@' ${IOAHCIBlockStorage}

		if [[ $(md5 -q ${IOAHCIBlockStorage}) == $(md5 -q ${backupFile}) ]]; then
		    echo "Le patch de '${IOAHCIBlockStorage}' a echoué. Votre Kext IOAHCIBlockStorage n'est pas modifié."
		    logger \"-- [${scriptName}] : Le patch de '${IOAHCIBlockStorage}' a echoué. Votre Kext IOAHCIBlockStorage est inchangé.\"
		    deleteTmpFiles
		    exit 1
		else
		    touch /System/Library/Extensions/
		    # for Yosemite only rebuild kext cache manually (could take a while) / uniquement si modification effectuée
			if [[ ${SystemOSMinor} -eq 10 ]] && [[ ${SystemOSPoint} -ge 0 ]] && [[ ${SystemOSPoint} -lt 4 ]]; then
				kextcache -m /System/Library/Caches/com.apple.kext.caches/Startup/Extensions.mkext /System/Library/Extensions
			fi
		    # Force a reboot of the system's kernel extension cache
			echo "Nous rebootons."
			logger \"-- [${scriptName}] : trimEnabler reboote la machine pour terminer.\"
			echo "${SystemOS}" > ${historyKextPatches}
		    deleteTmpFiles
		    shutdown -r now
		fi
	fi
fi
deleteTmpFiles
exit 0