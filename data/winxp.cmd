sc config TlntSvr start= auto
net user BOXES_USERNAME BOXES_PASSWORD /add /passwordreq:no
net localgroup administrators BOXES_USERNAME /add
net accounts /maxpwage:unlimited
copy a:\BOXES_USERNAME.bmp "c:\Documents and Settings\All Users\Application Data\Microsoft\User Account Pictures"
REGEDIT /S a:\winxp.reg
EXIT
