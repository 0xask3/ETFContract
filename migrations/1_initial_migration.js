const IndexVault = artifacts.require("IndexVault");
const Router = artifacts.require("IUniswapV2Router02");
const currTime = Number(Math.round(new Date().getTime() / 1000));

module.exports = async function(deployer) {
  await deployer.deploy(
    IndexVault,
    '0x77c21c770Db1156e271a3516F89380BA53D594FA',
    ['0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684'],
    [100]
  );
};
