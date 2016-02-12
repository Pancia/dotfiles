#INSTALLS
hash brew || ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
hash ag || brew install ag
hash rename || brew install rename
hash bro || brew install bro
hash tree || brew install tree
hash planck || brew install planck
hash zsh || brew install zsh
hash tmux || brew install tmux
mkdir -p ~/.vim/undo

[[ -e fonts ]] || (git clone https://github.com/powerline/fonts.git && ./fonts/install.sh)

#*RC INSTALLS
cp .vimrc        ~/.vimrc
cp .vimperatorrc ~/.vimperatorrc
cp .agignore     ~/.agignore
cp .zshrc        ~/.zshrc
cp .zshenv       ~/.zshenv
ln -f tmux.conf  ~/.tmux.conf

#vim/ftplugin
mkdir -p ~/.vim/ftplugin
for i in $(ls vim/ftplugin); do
    ln -f vim/ftplugin/$i ~/.vim/ftplugin/$i
done

exec zsh
