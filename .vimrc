set nocompatible " be iMproved, required

" autoinstall vim-plug
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  silent !curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" initialize vim-plug
call plug#begin('~/.vim/bundle')

" color schemes
Plug 'crusoexia/vim-monokai'

" plugins
Plug '/usr/local/opt/fzf' | Plug 'junegunn/fzf.vim'
Plug 'AndrewRadev/splitjoin.vim'
Plug 'Quramy/tsuquyomi'
Plug 'Shougo/vimproc', {'do' : 'make'}
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'airblade/vim-gitgutter'
Plug 'benmills/vimux'
Plug 'editorconfig/editorconfig-vim'
Plug 'godlygeek/tabular'
Plug 'janko-m/vim-test'
Plug 'kien/ctrlp.vim'
Plug 'scrooloose/nerdtree'
Plug 'terryma/vim-multiple-cursors'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-surround'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'w0rp/ale'

" syntax files
Plug 'chr4/nginx.vim'
Plug 'digitaltoad/vim-jade'
Plug 'elixir-lang/vim-elixir'
Plug 'elzr/vim-json'
Plug 'fatih/vim-go'
Plug 'hashivim/vim-terraform'
Plug 'kchmck/vim-coffee-script'
Plug 'leafgarland/typescript-vim'
Plug 'mxw/vim-jsx'
Plug 'nono/vim-handlebars'
Plug 'pangloss/vim-javascript'
Plug 'robbles/logstash.vim'
Plug 'tpope/vim-markdown'
Plug 'voithos/vim-python-syntax'

" needs to be last
Plug 'ryanoasis/vim-devicons'

" end vim-plug definition
call plug#end()

" set leader
let mapleader = '-'

" basic config
syntax on
set number
set ruler
set cursorline
highlight ColorColumn ctermbg=2
set colorcolumn=121

" fonts and icons
set encoding=utf8
set guifont=MesloLGSNerdFontCompleteMono---RegularForPowerline:h11
set background=dark
set t_Co=256
colorscheme monokai

" tabs
set expandtab
set smarttab
set shiftwidth=2
set softtabstop=2
autocmd FileType make set noexpandtab shiftwidth=8 softtabstop=0

" better moving between windows
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" disable backups
set nobackup
set nowritebackup
set noswapfile

" NERDTree
autocmd FileType nerdtree setlocal nolist

" auto start NERDTree automatically
" autocmd vimenter * NERDTree

" airline config
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1

" fzf settings
" enable fzf
nnoremap <C-p> :FZF --multi<CR>

" fzf layout
let g:fzf_layout = { 'down': '~30%' }

" tsuquyomi config
let g:tsuquyomi_disable_quickfix = 1
if !exists('g:ycm_semantic_triggers')
  let g:ycm_semantic_triggers = {}
endif
let g:ycm_semantic_triggers['typescript'] = ['.']

" javascript config
let g:javascript_opfirst = 1

" also autosave when going to insert mode
inoremap kj <Esc>:w<CR>
inoremap jk <Esc>:w<CR>

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

" remove any trailing whitespace that is in the file
autocmd BufRead,BufWrite * if ! &bin | silent! %s/\s\+$//ge | endif

" lists invisible chars
set list listchars=tab:❘-,trail:·,extends:»,precedes:«,nbsp:×

" ctrl p settings
" disable it in favor of fzf
let g:loaded_ctrlp = 1

" Ignore some folders and files for CtrlP indexing
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\.git$\|\.yardoc\|node_modules\|log\|tmp\|coverage$',
  \ 'file': '\.so$\|\.dat$|\.DS_Store$'
  \ }

" vim test
let test#strategy = "vimux"

nmap <silent> <leader>t :TestNearest<CR>
nmap <silent> <leader>f :TestFile<CR>
nmap <silent> <leader>r :TestSuite<CR>```

" tabular key bindings
nmap <leader>a= :Tabularize /=<CR>
vmap <leader>a= :Tabularize /=<CR>
nmap <leader>a: :Tabularize /:\zs<CR>
vmap <leader>a: :Tabularize /:\zs<CR>

" multiple cursor settings
let g:multi_cursor_exit_from_visual_mode=0

" keep at least 5 lines below the cursor
set scrolloff=5

" enable mouse support
set mouse=a

" close buffer when tab is closed
set nohidden

" persistent undo
set undodir=~/.vim/undo/
set undofile

" load local .vimrc
set exrc
set secure

" git gutter
set updatetime=100
highlight GitGutterAdd guifg=#A6E22D guibg=#2D2E27 ctermfg=148 ctermbg=235
highlight GitGutterChange guifg=#E6DB74 guibg=#2D2E27 ctermfg=186 ctermbg=235
highlight GitGutterDelete guifg=#e73c50 guibg=#2D2E27 ctermfg=196 ctermbg=235

" terraform
let g:terraform_align=1
autocmd FileType terraform setlocal commentstring=#%s
let g:terraform_fmt_on_save=1

" golang
let g:go_fmt_command = "goimports"

" docker
autocmd BufNewFile,BufRead Dockerfile.* set syntax=dockerfile

" yaml
autocmd BufNewFile,BufRead *yaml.tpl set syntax=yaml
