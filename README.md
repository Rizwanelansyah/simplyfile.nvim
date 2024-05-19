# simplyfile.nvim
simple file explorer plugin for neovim

![Preview](https://raw.githubusercontent.com/Rizwanelansyah/simplyfile.nvim/main/preview.png "Preview")

## requirements
- neovim 0.9.5 or higher
- [patched font](https://www.nerdfonts.com/)
- (optional) [nvim-tree-webdevicons](https://github.com/nvim-tree/nvim-web-devicons)

## installation
With [packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use 'Rizwanelansyah/simplyfile.nvim'
```

With [lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
{ 'Rizwanelansyah/simplyfile.nvim' }
```

## config
config and default value
```lua
require("simplyfile").setup {
    border = {
        left = "rounded",
        main = "double",
        right = "rounded",
    },
    derfault_keymaps = true,
    keymaps = {
        --- your custom keymaps
        --- {dir} have following field
        --- name: name of file/folder
        --- absolute: absolute path of file/folder
        --- icon: the nerd fonts icon
        --- hl: highlight group name for icon
        --- filetype: type of file
        --- is_folder: folder or not
        ["lhs"] = function(dir) --[[ some code ]] end
    }
}
```

## usages
- `:SimplyFileOpen` open the explorer or `require("simplyfile").open()`
- `:SimplyFileClose` close the explorer or `require("simplyfile").close()`

## TODO:
- ❌ clipboards
- ✅ search bar
- ❌ filter
- ❌ sort
