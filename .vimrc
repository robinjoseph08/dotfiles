set nocompatible " be iMproved, required
filetype off     " required

function! BuildYCM(info)
  if a:info.status == 'installed' || a:info.force
    !./install.sh
  endif
endfunction

function! Installjshint(info)
  if a:info.status == 'installed' || a:info.force
    !npm install -g jshint
  endif
endfunction

call plug#begin('~/.vim/plugged')

" Aesthetic
Plug 'crusoexia/vim-monokai'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'airblade/vim-gitgutter'
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
Plug 'ryanoasis/vim-devicons'
Plug 'junegunn/goyo.vim'

" File Shortcuts
Plug 'mileszs/ack.vim'
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'tpope/vim-eunuch'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-rhubarb'

" Code Shortcuts
Plug 'godlygeek/tabular'
Plug 'scrooloose/nerdcommenter'
if v:version > 703
  Plug 'Valloric/YouCompleteMe', { 'do': function('BuildYCM') }
endif

"" Syntax Plugs
Plug 'sheerun/vim-polyglot'
Plug 'pangloss/vim-javascript'
Plug 'jelera/vim-javascript-syntax'
Plug 'w0rp/ale'

" testing
Plug 'janko-m/vim-test'
Plug 'benmills/vimux'

call plug#end()

" crusoexia/vim-monokai Theme
syntax on
colorscheme monokai
set t_Co=256

" Open .vimrc
nnoremap <leader>ev :vsplit $MYVIMRC<cr>

" Source .vimrc
nnoremap <leader>sv :source $MYVIMRC<cr>

" basic config
set number
set ruler
set colorcolumn=121
set autoread                          " auto read edits from outside
set clipboard=unnamed                 " Use OS clipboard
set undodir=~/.vim/undo/
set undofile

" fonts and icons
set encoding=utf-8
set guifont=Droid\ Sans\ Mono\ for\ Powerline\ Plus\ Nerd\ File\ Types:h11

" Visually moves up and down (for wrapped lines)
nnoremap k gk
nnoremap j gj

" Have left and right movement wrap lines
set whichwrap+=<,>,h,l,[,]

" Move around more quickly
nnoremap H 0
vnoremap H 0
nnoremap L $
vnoremap L $

" better moving between windows
noremap <C-j> <C-W>j
noremap <C-k> <C-W>k
noremap <C-h> <C-W>h
noremap <C-l> <C-W>l

" Move between buffers with tab and shift-tab
nnoremap <Tab> :bnext<CR>
nnoremap <S-Tab> :bprevious<CR>

" fzf Buffers
nnoremap <Leader>b :Buffers<CR>
nnoremap <C-p> :Files<CR>
"nnoremap <Leader>r :Tags<CR>

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

" vim-test
let test#strategy = 'vimux'

nmap <silent> <leader>t :TestNearest<CR>
nmap <silent> <leader>f :TestFile<CR>
nmap <silent> <leader>s :TestSuite<CR>

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
inoremap jk <Esc>
inoremap kj <Esc>

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
highlight ColorColumn ctermbg=2

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
"set list listchars=tab:❘-,trail:·,extends:»,precedes:«,nbsp:×

" ctrl p settings
" Ignore some folders and files for CtrlP indexing
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\.git$\|\.yardoc\|node_modules\|tmp\|coverage$',
  \ 'file': '\.so$\|\.dat$|\.DS_Store$'
  \ }

" tabular key bindings
nmap <leader>t= :Tabularize /=<CR>
vmap <leader>t= :Tabularize /=<CR>
nmap <leader>t: :Tabularize /:\zs<CR>
vmap <leader>t: :Tabularize /:\zs<CR>
nmap <leader>t, :Tabularize /,\zs<CR>
vmap <leader>t, :Tabularize /,\zs<CR>

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

let @j = 'cc[ENG-####](https://lobsters.atlassian.net/browse/ENG-####)jk'

function! ProseMode()
  call goyo#execute(0, [])
  set spell noci nosi noai nolist noshowmode noshowcmd
  set complete+=s
  set bg=light
endfunction

command! ProseMode call ProseMode()
nmap \p :ProseMode<CR>
