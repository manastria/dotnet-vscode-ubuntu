# Sur la machine connectée
curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l ./vsdbg -r linux-x64

# Puis copier vers la VM
scp -r ./vsdbg etudiant@vm-tp:/home/etudiant/.vsdbg