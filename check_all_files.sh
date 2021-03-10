#!/bin/zsh
cd ..;
BASE_DIRECTORY=$(pwd);
echo "BASE DIRECTORY: $BASE_DIRECTORY"
cd mysql_replayer;

for f in ../mutual-production/*; do
  echo "Now starting file $f"
  bin/replay -f $f -d mysql://root:test@127.0.0.1:3306/replay_test;
  # Now that we've successfully generated files, we need to check
  # Them for errors
  # I'm going to shamelessly let things fail here.
  filename=${f##.*/};
  if test -f "changes/$filename.changes.txt"; then
    echo "Executing changes...";
    bin/execute-changes changes/$filename.changes.txt ../mutual-production/$filename;
    echo "Displaying diff...";
    diff --color ../mutual-production/$filename ../mutual-production/$filename.modified.txt;
    # echo "Press enter to continue with these changes or ctrl+c to abort.";
    # read line;
    echo "Replacing file with edited version"
    if test -f "../mutual-production/$filename.modified.txt"; then
      echo "Replacing old file with modified version"
      rm ../mutual-production/$filename;
      mv ../mutual-production/$filename.modified.txt ../mutual-production/$filename
    fi
    rm changes/$filename.changes.txt
  fi
done
