"""Custom Robot Framework keywords for network-level checks.

Stdlib only (socket, ssl, datetime) - no extra dependencies.
Each public method becomes a Robot Framework keyword;
AssertionError = test failure.
"""

import socket
import ssl
from datetime import datetime, timezone


class NetworkLibrary:
    """Network-layer test keywords: DNS, TLS certificates, TCP ports."""

    ROBOT_LIBRARY_SCOPE = "GLOBAL"

    def dns_should_resolve(self, hostname: str) -> str:
        """Fails unless *hostname* resolves to at least one IP address.

        Returns the first resolved IP (assignable in Robot Framework).
        Example:
        | ${ip}= | DNS Should Resolve | grid.connectedovals.com |
        """
        try:
            infos = socket.getaddrinfo(hostname, None)
        except socket.gaierror as exc:
            raise AssertionError(f"DNS resolution failed for {hostname!r}: {exc}")
        ip = infos[0][4][0]
        unique_ips = {info[4][0] for info in infos}
        print(f"*INFO* {hostname} resolved to {ip} ({len(unique_ips)} unique IPs)")
        return ip

    def tls_certificate_should_be_valid_for_days(
        self, hostname: str, min_days: int = 14, port: int = 443
    ) -> int:
        """Fails if the server's TLS certificate expires in less than *min_days* days.

        Connects with full verification (hostname + trusted CA chain),
        reads the certificate's notAfter date, returns days remaining.
        Example:
        | ${days}= | TLS Certificate Should Be Valid For Days | grid.connectedovals.com | 14 |
        """
        context = ssl.create_default_context()
        try:
            with (
                socket.create_connection((hostname, port), timeout=10) as sock,
                context.wrap_socket(sock, server_hostname=hostname) as tls,
            ):
                cert = tls.getpeercert()
        except ssl.SSLCertVerificationError as exc:
            raise AssertionError(
                f"Certificate verification FAILED for {hostname}: {exc}"
            )
        # TimeoutError is a subclass of OSError
        except OSError as exc:
            raise AssertionError(f"Could not connect to {hostname}:{port}: {exc}")

        not_after = datetime.strptime(cert["notAfter"], "%b %d %H:%M:%S %Y %Z").replace(
            tzinfo=timezone.utc
        )
        days_left = (not_after - datetime.now(timezone.utc)).days
        print(
            f"*INFO* {hostname} cert expires {not_after:%Y-%m-%d} ({days_left} days left)"
        )

        if days_left < int(min_days):
            raise AssertionError(
                f"Certificate for {hostname} expires in {days_left} days "
                f"minimum requires: {min_days} days"
            )
        return days_left

    def port_should_be_open(
        self, hostname: str, port: int, timeout: float = 5.0
    ) -> None:
        """Fails unless a TCP connection to *hostname*:*port* succeeds.

        Example:
        | Port Should Be Open | grid.connectedovals.com | 443 |
        """
        try:
            with socket.create_connection(
                (hostname, int(port)), timeout=float(timeout)
            ):
                print(f"*INFO* {hostname}:{port} is open")
        # TimeoutError and ConnectionRefusedError are subclasses of OSError
        except OSError as exc:
            raise AssertionError(f"Port {port} on {hostname} is NOT reachable: {exc}")

    def port_should_be_closed(
        self, hostname: str, port: int, timeout: float = 3.0
    ) -> None:
        """Fails if a TCP connection to *hostname*:*port* SUCCEEDS (negative scenario).

        Example:
        | Port Should Be Closed | grid.connectedovals.com | 8080 |
        """
        try:
            with socket.create_connection(
                (hostname, int(port)), timeout=float(timeout)
            ):
                pass
        # TimeoutError and ConnectionRefusedError are subclasses of OSError
        except OSError:
            print(f"*INFO* {hostname}:{port} is closed/filtered - as expected")
            return
        raise AssertionError(f"Port {port} on {hostname} is unexpectedly OPEN")
