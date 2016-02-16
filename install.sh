#INSTALLS
hash brew || (ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" &&
    brew tap homebrew/bundle &&
    brew bundle)

#FONTS
[[ -e fonts ]] || (git clone https://github.com/powerline/fonts.git && ./fonts/install.sh)

#*RC INSTALLS
cp .vimrc        ~/.vimrc
cp .vimperatorrc ~/.vimperatorrc
cp .agignore     ~/.agignore
cp .zshrc        ~/.zshrc
cp .zshenv       ~/.zshenv

#VIM
mkdir -p ~/.vim/undo
#.ftplugin
mkdir -p ~/.vim/ftplugin
for i in $(ls vim/ftplugin); do
    ln -f vim/ftplugin/$i ~/.vim/ftplugin/$i
done

#NVIM
mkdir -p ~/.config/nvim/ftplugin
for i in $(ls nvim); do
    ln -f ./nvim/$i ~/.config/nvim/$i
done
for i in $(ls nvim-ftplugin); do
    ln -f ./nvim-ftplugin/$i ~/.config/nvim/ftplugin/$i
done

#ENGAGE
exec zsh
