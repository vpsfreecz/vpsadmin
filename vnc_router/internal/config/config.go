package config

import (
	"encoding/json"
	"fmt"
	"os"
)

type Config struct {
	ListenAddr            string   `json:"listen_addr"`
	NoVNCDir              string   `json:"novnc_dir"`
	RabbitMQURL           string   `json:"rabbitmq_url"`
	MetricsAllowedSubnets []string `json:"metrics_allowed_subnets"`
}

// LoadFiles loads configs in order. Later files override earlier ones.
// Example: LoadFiles("base.json", "nixos.json", "secrets.json")
func LoadFiles(paths []string) (*Config, error) {
	if len(paths) == 0 {
		return nil, fmt.Errorf("at least one config file is required")
	}

	cfg := &Config{}

	for _, p := range paths {
		layer, err := readJSONConfig(p)
		if err != nil {
			return nil, fmt.Errorf("read config %q: %w", p, err)
		}
		merge(cfg, layer)
	}

	if err := validate(cfg); err != nil {
		return nil, err
	}

	return cfg, nil
}

func readJSONConfig(path string) (*Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var c Config
	if err := json.Unmarshal(b, &c); err != nil {
		return nil, err
	}
	return &c, nil
}

// merge overwrites dst with non-zero values from src.
func merge(dst, src *Config) {
	if src.ListenAddr != "" {
		dst.ListenAddr = src.ListenAddr
	}
	if src.NoVNCDir != "" {
		dst.NoVNCDir = src.NoVNCDir
	}
	if src.RabbitMQURL != "" {
		dst.RabbitMQURL = src.RabbitMQURL
	}
	if len(src.MetricsAllowedSubnets) > 0 {
		dst.MetricsAllowedSubnets = src.MetricsAllowedSubnets
	}
}

func validate(c *Config) error {
	if c.ListenAddr == "" {
		return fmt.Errorf("listen_addr is required")
	}
	if c.NoVNCDir == "" {
		return fmt.Errorf("novnc_dir is required")
	}
	if c.RabbitMQURL == "" {
		return fmt.Errorf("rabbitmq_url is required")
	}
	if len(c.MetricsAllowedSubnets) == 0 {
		return fmt.Errorf("metrics_allowed_subnets is required and must contain at least one subnet")
	}
	return nil
}
