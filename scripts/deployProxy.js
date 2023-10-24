const hre = require('hardhat');
const { verify } = require('../jshelpers/verifyContract')

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log('Deploying contracts with the account: ' + deployer.address);

  // Deploy AvatarContracts first
  const AvatarContracts = await hre.ethers.getContractFactory('AvatarContracts', {});

  const avatarContracts = await AvatarContracts.deploy();

  await avatarContracts.waitForDeployment();

  await avatarContracts.deploymentTransaction().wait(6);

  const avatarContractsAddress = await avatarContracts.getAddress();

  await verify(avatarContractsAddress, []);

  const RCAXTokenV2 = await hre.ethers.getContractFactory('RCAXTokenV2', {
    libraries: {
      'AvatarContracts': avatarContractsAddress
    }
  });

  const rcaxToken = await hre.upgrades.deployProxy(
      RCAXTokenV2,
      [deployer.address],
      {
        kind: 'uups',
        timeout: 300000
      }
  );

  await rcaxToken.waitForDeployment();

  await rcaxToken.deploymentTransaction().wait(6);

  const deployedProxyAddress = await rcaxToken.getAddress();

  console.log('RCAX Token deployed to:', deployedProxyAddress);

  await verify(deployedProxyAddress, []);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
