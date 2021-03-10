#!/bin/zsh
cd ..;
BASE_DIRECTORY=$(pwd);
echo "BASE DIRECTORY: $BASE_DIRECTORY"
cd mysql_replayer;

mkdir file-test-results

# And now we let GNU parallel work some magic for us
ls $BASE_DIRECTORY/mutual-production | parallel "./bin/replay -f ../mutual-production/{} -d mysql://root:test@127.0.0.1:3306/replay_test > file-test-results/{}.out.txt 2> file-test-results/{}.err.text"
