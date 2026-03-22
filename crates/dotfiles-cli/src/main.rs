mod commands;

fn main() {
    if let Err(err) = commands::run(std::env::args().skip(1).collect()) {
        dotfiles_core::support::die(&err);
    }
}
