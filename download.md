## Installation du dotnet sdk 10


```bash
apt install --install-suggests -y dotnet-sdk-10.0
```


## Téléchargement des extensions vscode

Téléchargement du « C# Dev Kit » :
```
https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-dotnettools/vsextensions/csdevkit/3.14.196/vspackage?targetPlatform=linux-x64
```

Téléchargement du vsdgb

```bash
# Sur la machine connectée
curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l ./vsdbg -r linux-x64

# Puis copier vers la VM
scp -r ./vsdbg etudiant@vm-tp:/home/etudiant/.vsdbg
```
