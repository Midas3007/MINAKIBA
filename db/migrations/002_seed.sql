-- Starting settings for Base mainnet. Base Sepolia rows are added when the test vault is deployed.
INSERT INTO vault_config (network, chain_id, usdc_address, treasury_address)
VALUES ('base', 8453, '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913', '0xcbf9f04c80451d043062daf27e36e55bbbe8512c');
INSERT INTO treasury_config (network) VALUES ('base'), ('base-sepolia');
INSERT INTO bot_settings (network) VALUES ('base'), ('base-sepolia');
INSERT INTO alert_config (id) VALUES (1);
INSERT INTO schema_migrations (version) VALUES ('002_seed');
