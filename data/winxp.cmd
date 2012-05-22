sc config TlntSvr start= auto
net user BOXES_USERNAME BOXES_PASSWORD /add /passwordreq:no
net localgroup administrators BOXES_USERNAME /add
net accounts /maxpwage:unlimited
REGEDIT /S a:\winxp.reg
EXIT
