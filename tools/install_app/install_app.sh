sudo udisksctl mount -b /dev/sdb1
sudo mkdir -p /run/media/root/DOLPHIN/apps/$1
sudo cp $2  /run/media/root/DOLPHIN/apps/$1/boot.dol
sudo umount /run/media/root/DOLPHIN
sudo rm -rf /run/media/root/DOLPHIN