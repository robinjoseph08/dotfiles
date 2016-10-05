set nocompatible " be iMproved, required
filetype off     " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" color schemes
Plugin 'crusoexia/vim-monokai'

" plugins
Plugin 'ryanoasis/vim-devicons'
Plugin 'AndrewRadev/splitjoin.vim'
Plugin 'Quramy/tsuquyomi'
Plugin 'Shougo/vimproc'
Plugin 'Xuyuanp/nerdtree-git-plugin'
Plugin 'airblade/vim-gitgutter'
Plugin 'godlygeek/tabular'
Plugin 'ctrlpvim/ctrlp.vim'
Plugin 'scrooloose/nerdcommenter'
Plugin 'scrooloose/nerdtree'
Plugin 'scrooloose/syntastic'
Plugin 'terryma/vim-multiple-cursors'
Plugin 'tiagofumo/vim-nerdtree-syntax-highlight'
Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'

" YouCompleteMe
if v:version > 703
  Plugin 'Valloric/YouCompleteMe'
endif

" syntax files
Plugin 'digitaltoad/vim-jade'
Plugin 'elixir-lang/vim-elixir'
Plugin 'elzr/vim-json'
Plugin 'leafgarland/typescript-vim'
Plugin 'nono/vim-handlebars'
Plugin 'pangloss/vim-javascript'
Plugin 'tpope/vim-markdown'
Plugin 'voithos/vim-python-syntax'

" All of your Plugins must be added before the following line
call vundle#end()                     " required

" basic config
syntax on
set number
set ruler
highlight ColorColumn ctermbg=2
set colorcolumn=121
set autoread                          " auto read edits from outside
set clipboard=unnamed                 " Use OS clipboard
set undodir=~/.vim/undo/
set undofile

" fonts and icons
set encoding=utf-8
set guifont=Droid\ Sans\ Mono\ for\ Powerline\ Plus\ Nerd\ File\ Types:h11
set background=dark
set t_Co=256

" Visually moves up and down (for wrapped lines)
nnoremap k gk
nnoremap j gj

" Move around more quickly
nnoremap H 0
vnoremap H 0
nnoremap L $
vnoremap L $

" better moving between windows
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" tabs/indents
set shiftwidth=2                      " Default tab settings
set softtabstop=2
filetype plugin on                    " required
filetype indent on                    " change indent based on file type
set expandtab
set smarttab
set autoindent
set smarttab

" change split opening to below and right
set splitbelow
set splitright

" disable backups
set nobackup
set nowritebackup
set noswapfile

" nerdtree
"autocmd FileType nerdtree setlocal nolist

" auto start NERDTree
"autocmd vimenter * NERDTree

" airline config
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1

" syntastic config
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_javascript_checkers = ['eslint']
let g:syntastic_typescript_checkers = ['tsuquyomi']

" tsuquyomi config
let g:tsuquyomi_disable_quickfix = 1
if !exists('g:ycm_semantic_triggers')
  let g:ycm_semantic_triggers = {}
endif
let g:ycm_semantic_triggers['typescript'] = ['.']
let g:ycm_autoclose_preview_window_after_completion = 1

" also autosave when going to insert mode
inoremap jk <Esc>:w<CR>
inoremap kj <Esc>:w<CR>

" map semicolon to colon
nnoremap ; :

" leave showtabline as default (for now)
set showtabline=1

" searching options
set incsearch
set showcmd
set ignorecase
set smartcase
set hlsearch

" window options
set showmode
set showcmd
set ruler
set ttyfast
set backspace=indent,eol,start
set laststatus=2

" escape search highliting by hitting return
nnoremap <CR> :noh<CR><CR>

colorscheme monokai

" remove any trailing whitespace that is in the file
autocmd BufRead,BufWrite * if ! &bin | silent! %s/\s\+$//ge | endif

" lists invisible chars
"set list listchars=tab:❘-,trail:·,extends:»,precedes:«,nbsp:×

" ctrl p settings
" Ignore some folders and files for CtrlP indexing
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\.git$\|\.yardoc\|node_modules\|log\|tmp\|coverage$',
  \ 'file': '\.so$\|\.dat$|\.DS_Store$'
  \ }

" tabular key bindings
nmap <leader>t= :Tabularize /=<CR>
vmap <leader>t= :Tabularize /=<CR>
nmap <leader>t: :Tabularize /:\zs<CR>
vmap <leader>t: :Tabularize /:\zs<CR>

" multiple cursor settings
let g:multi_cursor_exit_from_visual_mode=0

" fix aligned chains in javascript
let g:javascript_opfirst=1

" keep at least 5 lines below the cursor
set scrolloff=5

" enable mouse support
set mouse=a

" close buffer when tab is closed
set nohidden

" close vim if all tabs are closed
"autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTreeType") && b:NERDTreeType == "primary") | q | endif

