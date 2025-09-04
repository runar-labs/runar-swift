#include "runar_ffi.h"

// Linker shim to fail with a clear message if the Rust library isn't linked.
__attribute__((used)) static void __ensure_linkage_symbols_present(void) {
    (void)rn_free;
    (void)rn_string_free;
    (void)rn_keys_new;
    (void)rn_keys_free;
    (void)rn_keys_node_get_public_key;
    (void)rn_keys_node_get_node_id;
    (void)rn_keys_node_generate_csr;
    (void)rn_keys_mobile_process_setup_token;
    (void)rn_keys_node_install_certificate;
    (void)rn_transport_new_with_keys;
    (void)rn_transport_free;
    (void)rn_transport_start;
    (void)rn_transport_poll_event;
    (void)rn_transport_connect_peer;
    (void)rn_transport_disconnect_peer;
    (void)rn_transport_is_connected;
    (void)rn_transport_update_local_node_info;
    (void)rn_transport_request;
    (void)rn_transport_publish;
    (void)rn_transport_complete_request;
    (void)rn_transport_stop;
    (void)rn_transport_local_addr;
}


