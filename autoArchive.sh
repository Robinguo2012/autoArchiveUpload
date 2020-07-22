#!/bin/sh

echo "Please enter number you want to export ? [1:appStore  2:ad-hoc]"

read number
while([[ $number != 1 ]] && [[ $number != 2 ]])
do
echo "Error! should enter 1 or 2"
echo "Please enter the number you want to export? [1:appStore  2:ad-hoc]"
read number
done

cd .. # 进入工程主目录

#工程绝对路径
project_path=$(cd `dirname $0`; pwd)


# 配置文件路径
projectPlistPath="${project_path}/BaseProject/Info.plist"


# 读取打包信息
configuration_file="./AutoArchive/Config/BuildConfiguration.plist"

project_name=$(/usr/libexec/PlistBuddy -c "Print project_name" ${configuration_file}) #工程名称
scheme=$(/usr/libexec/PlistBuddy -c "Print scheme" ${configuration_file}) #scheme
workspace=$(/usr/libexec/PlistBuddy -c "Print workspace" ${configuration_file}) #workspace
configuration=$(/usr/libexec/PlistBuddy -c "Print configuration" ${configuration_file}) #打包模式 Release/Debug
bundleId=$(/usr/libexec/PlistBuddy -c "Print bundle_id" ${configuration_file})

# 打包文件的路径,不存在就创建
build_path="${project_path}/AutoArchive/Build"

if [ ! -d $build_path ];
then
mkdir ${build_path}
fi

#log日志文件
log_path="${project_path}/AutoArchive/Log"
log_file="${log_path}/archive.log"
# IPA 路径
exportIpaPath="${project_path}/AutoArchive/IPADir"

#检查日志文件是否存在
if [ ! -f "$log_path" ]; 
then
  mkdir ${log_path}
  touch ${log_file}
fi


if [ ! -d ${exportIpaPath} ];
then
mkdir ${exportIpaPath}
fi

pod install

# 修改 exportOptions.plist 路径
if [ $number == 1 ];then
echo "上传到AppStore"
# 导出plist 文件所在路径
exportPlistPath="./AutoArchive/Config/AppStoreExportOptionsPlist.plist"
configuration="Release"
else
echo "上传到蒲公英"
exportPlistPath="./AutoArchive/Config/ADHOCExportOptionsPlist.plist"
configuration="Release"

fi

CODE_SIGN_IDENTITY=$(/usr/libexec/PlistBuddy -c "Print signingCertificate" ${exportPlistPath})
PROVISIONING_PROFILE=$(/usr/libexec/PlistBuddy -c "Print provisioningProfiles:${bundleId}" ${exportPlistPath})

echo ${CODE_SIGN_IDENTITY}
echo ${PROVISIONING_PROFILE}
echo ${scheme}
echo ${project_name}
echo ${project_path}
echo ${configuration}
echo ${exportPlistPath}

compileAndExportIPA(){
  echo "/------清理工程------/"

  xcodebuild \
  clean -configuration ${configuration} -quiet || exit

  echo "/-----编译工程------/"

  #时间戳
  buildTime=$(date +%Y%m%d%H%M)
  echo "\r\r$(date +%Y年%m月%d日%H时%M分)：${ipa_name}开始打包" >> $log_file
  archivePath="${build_path}/${project_name}_${buildTime}.xcarchive"

  xcodebuild \
  archive -workspace ${project_path}/${project_name}.xcworkspace \
  -scheme ${scheme} \
  -configuration ${configuration} \
  -archivePath ${archivePath} \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" \
  PROVISIONING_PROFILE="${PROVISIONING_PROFILE}" \
   -quiet || exit
 
  echo "/-----导出IPA------/"

  xcodebuild -exportArchive -archivePath "${build_path}/${project_name}_${buildTime}.xcarchive" \
  -configuration ${configuration} \
  -exportPath   ${exportIpaPath} \
  -exportOptionsPlist ${exportPlistPath} \
   -quiet || exit

  ipaFullPath="$exportIpaPath/${scheme}.ipa"

  if [ -e ${ipaFullPath} ]; then
    echo "/------IPA导出完成------/"
    open $exportIpaPath
    return 1
  else 
    echo "/-----IPA导出失败-------/"
    return 0
  fi

}


uploadIPAToThird() {
  echo "正在上传第三方平台 ipa 地址：${ipaFullPath}"

  
  MSG=`git log -1 --pretty=%B`
  
  # 上传到 fir
  # api_token=$(/usr/libexec/PlistBuddy -c "Print Fir:api_token" './AutoArchive/Config/BuildConfiguration.plist')
  # fir p ${ipaFullPath} -T ${api_token}
  # curl -F 'file=@/tmp/example.ipa' 
  #      -F '_api_key=a6a4bb6ecff2a65813f9ff5f3742e104' 
  #     https://www.pgyer.com/apiv2/app/upload

  # 蒲公英上传
  curl -F "file=@${ipaFullPath}"  \
  -F "_api_key=a6a4bb6ecff2a65813f9ff5f3742e104" \
  -F "updateDescription=${MSG}"  https://www.pgyer.com/apiv2/app/upload >> ${log_file}

  webhook='https://oapi.dingtalk.com/robot/send?access_token=79aa97760c9dbb28067df7d8037cc946d470338ec05b7837c2d0be657ee1d7fd'
  curl $webhook -H 'Content-Type: application/json' -d "
    {
        'msgtype': 'link',
        'link': {
            'title': 'iOS测试',
            'text': '${MSG}',
            'picUrl': '',
            'messageUrl':'https://www.pgyer.com/BV4N'
        },
        'at': {
            'isAtAll': false
        }
    }"

}

uploadToAppStore(){
# 上传到AppStore
  echo "正在上传AppStore"
  appleid=$(/usr/libexec/PlistBuddy -c "Print Apple:appleId" './AutoArchive/Config/BuildConfiguration.plist')
  appleIDPWD=$(/usr/libexec/PlistBuddy -c "Print Apple:applePwd" './AutoArchive/Config/BuildConfiguration.plist')

  echo "/-------验证IPA----------/"
  xcrun altool --validate-app \
   -f ${ipaFullPath} \
   -u "${appleid}" \
   -p "${appleIDPWD}" \
   -t ios --output-format xml > ./AutoArchive/result.plist


  echo "/----------上传IPA----------/"

  xcrun altool --upload-app \
  -f ${ipaFullPath} \
  -u  "${appleid}" \
  -p "${appleIDPWD}" \
  -t ios --output-format xml > ./AutoArchive/result.plist
  
  echo "/----------上传AppStore成功----------/"

}

uploadToTestflight() {
  # 上传到AppStore
  echo "正在上传AppStore"
  appleid=$(/usr/libexec/PlistBuddy -c "Print Apple:appleId" './AutoArchive/Config/BuildConfiguration.plist')
  appleIDPWD=$(/usr/libexec/PlistBuddy -c "Print Apple:applePwd" './AutoArchive/Config/BuildConfiguration.plist')

  echo "/-------验证IPA----------/"
  xcrun altool --validate-app \
   -f ${ipaFullPath} \
   -u "${appleid}" \
   -p "${appleIDPWD}" \
   -t ios --output-format xml > ./AutoArchive/result.plist


  echo "/----------上传IPA----------/"

  xcrun altool --upload-app \
  -f ${ipaFullPath} \
  -u  "${appleid}" \
  -p "${appleIDPWD}" \
  -t ios --output-format xml > ./AutoArchive/result.plist
  
  echo "/----------上传AppStore成功----------/"
}

uploaddSYMToBugly(){

  #Bugly 
  buglyAppKey=$(/usr/libexec/PlistBuddy -c "Print Bugly:buglyAppKey" './AutoArchive/Config/BuildConfiguration.plist')
  buglyAppId=$(/usr/libexec/PlistBuddy -c "Print Bugly:buglyAppId" './AutoArchive/Config/BuildConfiguration.plist')

  echo '/+++++++ 压缩dSYM文件 +++++++/'

  cd ${archivePath}/dSYMs
  zip -r -o ${project_name}.app.dSYM.zip "${project_name}.app.dSYM"
  echo '/+++++++ 压缩dSYM文件完成 +++++++/'

  echo '/+++++++ 上传dSYM文件 +++++++/'
  curl -k "https://api.bugly.qq.com/openapi/file/upload/symbol?app_key=$buglyAppKey&app_id=$buglyAppId" --form "api_version=1" --form "app_id=$buglyAppId" --form "app_key=$buglyAppKey" --form "symbolType=2"  --form "bundleId=${bundleId}" --form "productVersion=${new_mainVersion}(${new_mainBuild})" --form "channel=appstore" --form "fileName=$project_name.app.dSYM.zip" --form "file=@$archivePath/dSYMs/$project_name.app.dSYM.zip" --verbose
  echo '\n/+++++++ 上传dSYM文件结束 +++++++/'

}

incShortVersion(){
 #buglyAppKey=$(/usr/libexec/PlistBuddy -c "Print Bugly:buglyAppKey" './AutoArchive/Config/BuildConfiguration.plist')
  # /usr/libexec/PlistBuddy -c 'Set :Application:1 string "thi is app1"' info.plist
  currentShortInt=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionInt" ${projectPlistPath})
  let currentShortInt=currentShortInt+1
  /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionInt '${currentShortInt}'' ${projectPlistPath}
  echo "current short version ${currentShortInt}"

  # mainVersion=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" ${projectPlistPath})
  # mainBuild=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" ${projectPlistPath})

  # new_mainVersion=$mainVersion
  # new_mainBuild=$mainBuild
  # echo "main bundle version ${new_mainVersion} build ${new_mainBuild}"

}


if [ $number == 1 ] 
then
  incShortVersion
  compileAndExportIPA
  uploadToAppStore
  uploaddSYMToBugly

  # if [ $? == 1]
  #  then
    
  # fi
  
else

  compileAndExportIPA
  # echo "导出IPA 结果 $?"
  res=1
  if test $res -eq 1
  then
    uploadIPAToThird
  fi
fi


exit

# 注意在机器人中定义了iOS测试，如果消息中没有这个关键字就会提示 `no keyword in content`
# function SendMsgToDingding() {
    
# }

# https://help.apple.com/itc/apploader/#/apdSe850405a
# https://github.com/0x1306a94/xcodebuild_sh/blob/master/xcodebuild.sh





