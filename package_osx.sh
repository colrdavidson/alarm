if [[ "$1" == "" ]]; then
	APP_PATH="./bin/alarm.app"
else
	APP_PATH="$1"
fi

if [[ "$2" == "" ]]; then
	BIN_PATH="./bin/alarm"
else
	BIN_PATH="$2"
fi

rm -rf $APP_PATH
mkdir $APP_PATH
mkdir $APP_PATH/Contents
mkdir $APP_PATH/Contents/MacOS
mkdir $APP_PATH/Contents/resources
cp $BIN_PATH $APP_PATH/Contents/MacOS/.
cp resources/info.plist $APP_PATH/Contents/.
cp resources/icon.icns $APP_PATH/Contents/resources/.
