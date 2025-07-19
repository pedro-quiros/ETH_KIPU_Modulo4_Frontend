const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const DeployTokens = buildModule("DeployTokens", (m) => {
  const tokenETH = m.contract("TokenETH");
  const tokenKIPU = m.contract("TokenKIPU");

  const amount = 1000n * 10n ** 18n;
  const deployer = m.getAccount(0);

  m.call(tokenETH, "mint", [deployer, amount]);
  m.call(tokenKIPU, "mint", [deployer, amount]);

  return { tokenETH, tokenKIPU };
});

module.exports = DeployTokens;
