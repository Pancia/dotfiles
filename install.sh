cp .vimrc        $HOME/.vimrc
cp .bashrc       $HOME/.bashrc
cp .vimperatorrc $HOME/.vimperatorrc

mkdir -p .vim/ftplugin
for i in $(ls ./.vim/ftplugin); do
    ln ./.vim/ftplugin/$i $HOME/.vim/ftplugin/$i
done

exec bash
