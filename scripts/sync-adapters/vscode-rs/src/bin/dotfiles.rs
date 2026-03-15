#[path = "dotfiles/common.rs"]
mod common;
#[path = "dotfiles/commands.rs"]
mod commands;

fn main() {
    if let Err(err) = commands::run(std::env::args().skip(1).collect()) {
        common::die(&err);
    }
}
