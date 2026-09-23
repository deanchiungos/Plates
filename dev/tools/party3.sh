#!/bin/bash
# Three-device party: A hosts, B and C join, C logs a plate.
# The question is whether B ever hears about it.
A=C96DC32A-603D-4408-84EF-7A933FFFA931   # Anna, host
B=FDD278CB-351C-4D7C-803E-76A9951EB4B1   # Dean, guest
C=4FE35AED-CC70-4E85-A101-7446ECEB039E   # Mia,  guest
APP=/Users/ethangeppel/Documents/CodingProjects/Plates/ios/.build/Build/Products/Debug-iphonesimulator/Plates.app

for D in $A $B $C; do
  xcrun simctl terminate $D com.tagsmedia.tags 2>/dev/null
  xcrun simctl uninstall $D com.tagsmedia.tags 2>/dev/null
  xcrun simctl install $D "$APP"
done

xcrun simctl launch $A com.tagsmedia.tags -noCloud -asPlayer Anna -tab more -openParty -hostParty -partyCode ABCD >/dev/null
python3 -c "import time; time.sleep(5)"
xcrun simctl launch $B com.tagsmedia.tags -noCloud -asPlayer Dean -tab more -openParty -joinParty -partyCode ABCD >/dev/null
python3 -c "import time; time.sleep(10)"
# C joins last and logs Ohio through the real PlateLogger path.
xcrun simctl launch $C com.tagsmedia.tags -noCloud -asPlayer Mia -tab more -openParty -joinParty -partyCode ABCD -partyLog OH >/dev/null
python3 -c "import time; time.sleep(30)"

for pair in "A:$A" "B:$B" "C:$C"; do
  name=${pair%%:*}; udid=${pair##*:}
  store=$(xcrun simctl get_app_container $udid com.tagsmedia.tags data)/Library/Application\ Support/default.store
  echo "--- $name ---"
  echo -n "  roster: "; sqlite3 "$store" "select group_concat(ZNAME,',') from (select ZNAME from ZPLAYER order by ZJOINEDAT);" 2>/dev/null
  echo -n "  OH by:  "; sqlite3 "$store" "select coalesce(group_concat(p.ZNAME,','),'(absent)') from ZSIGHTING s left join ZPLAYER p on s.ZPLAYER=p.Z_PK where s.ZPLATECODE='OH';" 2>/dev/null
done
for D in $A $B $C; do xcrun simctl terminate $D com.tagsmedia.tags 2>/dev/null; done
