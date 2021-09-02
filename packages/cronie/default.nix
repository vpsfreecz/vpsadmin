{ lib, stdenv, fetchurl, sendmailPath ? "/run/wrappers/bin/sendmail" }:

stdenv.mkDerivation rec {
  pname = "cronie";
  version = "1.5.7";

  src = fetchurl {
    url = "https://github.com/cronie-crond/cronie/releases/download/cronie-${version}/cronie-${version}.tar.gz";
    sha256 = "sha256:1cqf689nxvd9jwjfwnh0m7b730pafwm4glgnxphmlvlq5spwz2sk";
  };

  postPatch = ''
    substituteInPlace ./anacron/global.h \
      --replace '"/usr/sbin/sendmail"' '"${sendmailPath}"'
    substituteInPlace ./src/cron.c \
      --replace '"/usr/sbin/sendmail"' '"${sendmailPath}"'

    cat >> src/pathnames.h <<__EOT__
    #undef MAILARG
    #define MAILARG "${sendmailPath}"

    #undef _PATH_DEFPATH
    #define _PATH_DEFPATH "/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    __EOT__

    # Implicit saved uids do not work here due to way NixOS uses setuid wrappers
    # (#16518).
    echo "#undef HAVE_SAVED_UIDS" >> src/externs.h
  '';

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"
  ];

  meta = with lib; {
    description = "Daemon that runs specified programs at scheduled times and related tools";
    homepage = "https://github.com/cronie-crond/cronie";
    license = with licenses; [ mit /* and */ bsd3 /* and */ isc /* and */ gpl2Plus ];
    platforms = platforms.unix;
    maintainers = [];
  };
}
