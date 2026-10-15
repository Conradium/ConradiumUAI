'use strict';

const DISCORD = 'https://discord.gg/9xYyyYuKap';
function help(message) {
  const text = String(message || 'Something went wrong');
  return text.includes(DISCORD) ? text : text + ' Help and updates: ' + DISCORD;
}
module.exports = { DISCORD, help };
