#![allow(clippy::trivial_regex)]

#[macro_use]
extern crate lazy_static;
extern crate num_cpus;

use crate::config::CONF;

use colored::{ColoredString, Colorize};
use git2::{Oid, Repository, Signature};
use i18n::LocalText;
use inflector::Inflector;
use regex::Regex;
use std::ffi::OsStr;
use std::{error, fmt, path, result, str};

pub mod cli;
pub mod config;
pub mod i18n;

// Subcommands
pub mod make;
pub mod setup;
pub mod status;

// Import stuff set by autoconf/automake at build time
pub static CONFIGURE_PREFIX: &str = env!["CONFIGURE_PREFIX"];
pub static CONFIGURE_BINDIR: &str = env!["CONFIGURE_BINDIR"];
pub static CONFIGURE_DATADIR: &str = env!["CONFIGURE_DATADIR"];

/// If all else fails, use this BCP-47 locale
pub static DEFAULT_LOCALE: &str = "en-US";

lazy_static! {
    /// Fontship version number as detected by `git describe --tags` at build time
    pub static ref VERSION: &'static str =
        option_env!("VERGEN_GIT_DESCRIBE").unwrap_or_else(|| env!("CARGO_PKG_VERSION"));
}

pub type Result<T> = result::Result<T, Box<dyn error::Error>>;

/// A type for our internal whoops
#[derive(Debug)]
pub struct Error {
    details: String,
}

impl Error {
    pub fn new(key: &str) -> Error {
        Error {
            details: LocalText::new(key).fmt(),
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.details)
    }
}

impl error::Error for Error {
    fn description(&self) -> &str {
        &self.details
    }
}

pub fn pname(input: &str) -> String {
    let seps = Regex::new(r"[-_]").unwrap();
    let spaces = Regex::new(r" ").unwrap();
    let title = seps.replace_all(input, " ").to_title_case();
    spaces.replace_all(&title, "").to_string()
}

/// Get repository object
pub fn get_repo() -> Result<Repository> {
    let path = CONF.get_string("path")?;
    Ok(Repository::discover(path)?)
}

pub fn commit(repo: Repository, oid: Oid, msg: &str) -> result::Result<Oid, git2::Error> {
    let prefix = "[fontship]";
    let commiter = repo.signature()?;
    let author = Signature::now("Fontship", commiter.email().unwrap())?;
    let parent = repo.head()?.peel_to_commit()?;
    let tree = repo.find_tree(oid)?;
    let parents = [&parent];
    repo.commit(
        Some("HEAD"),
        &author,
        &commiter,
        &[prefix, msg].join(" "),
        &tree,
        &parents,
    )
}

pub fn locale_to_language(lang: String) -> String {
    let re = Regex::new(r"[-_\.].*$").unwrap();
    let locale_frag = lang.as_str().to_lowercase();
    let lang = re.replace(&locale_frag, "");
    match &lang[..] {
        "c" => String::from("en"),
        _ => String::from(lang),
    }
}

pub fn format_font_version(version: String) -> String {
    let re = Regex::new(r"-r.*$").unwrap();
    String::from(re.replace(version.as_str(), ""))
}

/// Output welcome header at start of run before moving on to actual commands
pub fn show_welcome() {
    let welcome = LocalText::new("welcome").arg("version", VERSION.to_string());
    eprintln!("{} {}", "┏━".cyan(), welcome.fmt().cyan());
}

/// Output welcome header at start of run before moving on to actual commands
pub fn show_outro() {
    let outro = LocalText::new("outro");
    eprintln!("{} {}", "┗━".cyan(), outro.fmt().cyan());
}

/// Output header before starting work on a subcommand
pub fn show_header(key: &str) {
    let text = LocalText::new(key);
    eprintln!("{} {}", "┣━".cyan(), text.fmt().yellow());
}

pub fn display_check(key: &str, val: bool) {
    if CONF.get_bool("debug").unwrap() || CONF.get_bool("verbose").unwrap() {
        eprintln!(
            "{} {} {}",
            "┠─".cyan(),
            LocalText::new(key).fmt(),
            fmt_t_f(val)
        );
    };
}

/// Format a localized string just for true / false status prints
fn fmt_t_f(val: bool) -> ColoredString {
    let key = if val { "setup-true" } else { "setup-false" };
    let text = LocalText::new(key).fmt();
    if val {
        text.green()
    } else {
        text.red()
    }
}

#[cfg(unix)]
pub fn bytes2path(b: &[u8]) -> &path::Path {
    use std::os::unix::prelude::*;
    path::Path::new(OsStr::from_bytes(b))
}
#[cfg(windows)]
pub fn bytes2path(b: &[u8]) -> &path::Path {
    use std::str;
    path::Path::new(str::from_utf8(b).unwrap())
}
