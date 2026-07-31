//
// controller-vhid-bridge
//
// Bridges the Controller mac app to the Karabiner DriverKit virtual HID
// pointing device, so controller camera input appears to games as REAL
// hardware mouse motion (IOHID level), not synthetic CGEvents.
//
// Runs as root (the daemon socket is root-only). Listens on a unix socket
// (/tmp/controller-vhid.sock, mode 0666) for one line-based client:
//
//   p <buttons> <dx> <dy>\n     buttons: bit0=left bit1=right bit2=middle
//
// Build: see build.sh (needs the Karabiner-DriverKit-VirtualHIDDevice sources).
//

#include <atomic>
#include <csignal>
#include <cstring>
#include <iostream>
#include <mutex>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>

namespace {
constexpr const char* kSocketPath = "/tmp/controller-vhid.sock";
std::atomic<bool> exit_flag(false);
std::atomic<bool> pointing_ready(false);
std::atomic<int> client_fd(-1);

// Tell the app whether the virtual device is actually usable, so its status
// badge reflects the driver, not merely that this helper is reachable.
void report_ready(bool ready) {
  int fd = client_fd.load();
  if (fd < 0) return;
  std::string line = ready ? "ready 1\n" : "ready 0\n";
  ::write(fd, line.c_str(), line.size());
}
}

int main() {
  std::signal(SIGINT, [](int) { exit_flag = true; });
  std::signal(SIGTERM, [](int) { exit_flag = true; });
  std::signal(SIGPIPE, SIG_IGN);

  pqrs::dispatcher::extra::initialize_shared_dispatcher();

  std::mutex client_mutex;
  auto client = std::make_unique<pqrs::karabiner::driverkit::virtual_hid_device_service::client>();

  client->connected.connect([&client] {
    std::cout << "daemon connected; initializing virtual pointing" << std::endl;
    client->async_virtual_hid_pointing_initialize();
  });
  client->connect_failed.connect([](auto&& error_code) {
    std::cout << "connect_failed " << error_code << std::endl;
  });
  client->closed.connect([] {
    pointing_ready = false;
    std::cout << "daemon connection closed" << std::endl;
  });
  client->driver_activated.connect([](auto&& activated) {
    static std::optional<bool> prev;
    if (prev != activated) {
      std::cout << "driver_activated " << activated << std::endl;
      prev = activated;
    }
  });
  client->virtual_hid_pointing_ready.connect([](auto&& ready) {
    bool r = ready;
    if (pointing_ready != r) {
      std::cout << "pointing_ready " << r << std::endl;
      pointing_ready = r;
      report_ready(r);
    }
  });

  client->async_start();

  //
  // Unix socket server
  //

  ::unlink(kSocketPath);
  int server_fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (server_fd < 0) {
    std::cerr << "socket() failed" << std::endl;
    return 1;
  }
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  std::strncpy(addr.sun_path, kSocketPath, sizeof(addr.sun_path) - 1);
  if (::bind(server_fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
    std::cerr << "bind() failed" << std::endl;
    return 1;
  }
  ::chmod(kSocketPath, 0666);
  ::listen(server_fd, 1);

  std::cout << "listening on " << kSocketPath << std::endl;

  while (!exit_flag) {
    int fd = ::accept(server_fd, nullptr, nullptr);
    if (fd < 0) continue;
    std::cout << "app connected" << std::endl;
    client_fd = fd;
    report_ready(pointing_ready);

    // Fixed 4-byte records: [sync 0xA5][buttons][int8 dx][int8 dy].
    // Binary + fixed width keeps the app's real-time thread allocation-free.
    uint8_t chunk[4096];
    uint8_t rec[4];
    size_t have = 0;
    while (!exit_flag) {
      ssize_t n = ::read(fd, chunk, sizeof(chunk));
      if (n <= 0) break;

      for (ssize_t i = 0; i < n; ++i) {
        if (have == 0 && chunk[i] != 0xA5) continue; // resync
        rec[have++] = chunk[i];
        if (have < 4) continue;
        have = 0;

        if (!pointing_ready) continue;

        pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::pointing_input report;
        uint8_t buttons = rec[1];
        if (buttons & 1) report.buttons.insert(1); // left
        if (buttons & 2) report.buttons.insert(2); // right
        if (buttons & 4) report.buttons.insert(3); // middle
        report.x = rec[2];
        report.y = rec[3];

        std::lock_guard<std::mutex> lock(client_mutex);
        if (client) {
          client->async_post_report(report);
        }
      }
    }

    client_fd = -1;
    ::close(fd);
    std::cout << "app disconnected" << std::endl;

    // Release any held buttons when the app goes away
    if (pointing_ready) {
      pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::pointing_input report;
      std::lock_guard<std::mutex> lock(client_mutex);
      if (client) {
        client->async_post_report(report);
      }
    }
  }

  {
    std::lock_guard<std::mutex> lock(client_mutex);
    client = nullptr;
  }
  pqrs::dispatcher::extra::terminate_shared_dispatcher();
  return 0;
}
