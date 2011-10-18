all : gist-vim.zip

remove-zip:
	-rm doc/tags
	-rm gist-vim.zip

gist-vim.zip: remove-zip
	zip -r gist-vim.zip autoload plugin doc

release: gist-vim.zip
	vimup update-script gist.vim
