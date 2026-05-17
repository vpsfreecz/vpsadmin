const fs = require('fs');

function readFixtures() {
  const file = process.env.VPSADMIN_WEBUI_FIXTURES;

  if (!file) {
    throw new Error('VPSADMIN_WEBUI_FIXTURES is not set');
  }

  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

module.exports = {
  readFixtures,
};
