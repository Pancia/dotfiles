- ``` zsh
  echo -en "\e]0;string\a" #-- Set icon name and window title to string
  echo -en "\e]1;string\a" #-- Set icon name to string
  echo -en "\e]2;string\a" #-- Set window title to string
  
  # in $HOME/.zshrc
  precmd () { print -Pn "\e]0;$TITLE\a" }
  title() { export TITLE="$*" }
  
  # in $HOME/.zprofile
  case $TERM in
      xterm*)
          precmd () {print -Pn "\e]0;string\a"}
          ;;
  esac
  ```