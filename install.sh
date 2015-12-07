cp .vimrc        ~/.vimrc
cp .bashrc       ~/.bashrc
cp .vimperatorrc ~/.vimperatorrc
cp .agignore     ~/.agignore

mkdir -p .vim/ftplugin
for i in $(ls ./.vim/ftplugin); do
    ln -f ./.vim/ftplugin/$i ~/.vim/ftplugin/$i
done

exec bash
