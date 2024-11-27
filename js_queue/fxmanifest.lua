fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'
author 'joszza | JS' -- discordID 408939574958620683

version '1.0.0'


client_scripts {
    'modules/**/client/*.lua',
    'client/*.lua'
}


server_scripts {
    '@mysql-async/lib/MySQL.lua',
    'modules/**/server/*.lua',
    'server/*.lua'
}


shared_scripts {
    'config.lua',
    '@es_extended/imports.lua',
    '@ox_lib/init.lua'
}

files {
    'data/*.lua',
}