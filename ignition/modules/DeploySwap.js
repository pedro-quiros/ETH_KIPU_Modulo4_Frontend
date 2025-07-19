const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const DeploySwap = buildModule("DeploySwap", (m) => {
  const simpleSwap = m.contract("SimpleSwap");
  return { simpleSwap };
  
});

module.exports = DeploySwap;
