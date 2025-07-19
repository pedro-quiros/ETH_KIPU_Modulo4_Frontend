const contractAddress = "0x0ca0b198aA7c8b5128468cb00e2e2f4a39755059";
const TOKEN_ETH = "0xAed9E92eC7cafE15884Bd78179D014d0621d9461";
const TOKEN_KIPU = "0x9E5884e5799a9BC431B141B0Dc2D573bd27Eccd0";

const abi = [
  "function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] path, address to, uint deadline) external returns (uint[] memory amounts)",
  "function getPrice(address tokenA, address tokenB) public view returns (uint)",
  "function reserve(address tokenA, address tokenB) external view returns (uint)"
];

let provider, signer, contract;

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("connectButton").addEventListener("click", connectWallet);

  document.getElementById("swapTokenETHToTokenKIPU").addEventListener("click", () => {
    executeSwap(TOKEN_ETH, TOKEN_KIPU);
  });

  document.getElementById("swapTokenKIPUToTokenETH").addEventListener("click", () => {
    executeSwap(TOKEN_KIPU, TOKEN_ETH);
  });
});

async function connectWallet() {
  if (typeof window.ethereum === "undefined") {
    alert("Instalá MetaMask para continuar.");
    return;
  }

  try {
    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    signer = await provider.getSigner();
    contract = new ethers.Contract(contractAddress, abi, signer);
    const address = await signer.getAddress();
    document.getElementById("walletAddress").textContent = `Conectado: ${address}`;
    await updateBalances();
    await updatePrices();
  } catch (error) {
    console.error("Error al conectar:", error);
    alert("Error conectando la wallet.");
  }
}

async function updateBalances() {
  if (!signer) return;
  const address = await signer.getAddress();

  const tokenAbi = ["function balanceOf(address) view returns (uint256)"];
  const ethToken = new ethers.Contract(TOKEN_ETH, tokenAbi, provider);
  const kipuToken = new ethers.Contract(TOKEN_KIPU, tokenAbi, provider);

  const balanceETH = await ethToken.balanceOf(address);
  const balanceKIPU = await kipuToken.balanceOf(address);

  document.getElementById("balanceETH").textContent = ethers.formatUnits(balanceETH, 18);
  document.getElementById("balanceKIPU").textContent = ethers.formatUnits(balanceKIPU, 18);
}

async function updatePrices() {
  if (!contract) return;

  try {
    const priceEthToKipu = await contract.getPrice(TOKEN_ETH, TOKEN_KIPU);
    const priceKipuToEth = await contract.getPrice(TOKEN_KIPU, TOKEN_ETH);

    document.getElementById("priceETHtoKIPU").textContent = `ETH → KIPU: ${ethers.formatUnits(priceEthToKipu, 18)}`;
    document.getElementById("priceKIPUtoETH").textContent = `KIPU → ETH: ${ethers.formatUnits(priceKipuToEth, 18)}`;
  } catch (err) {
    console.error("Error obteniendo precios:", err);
  }
}

async function executeSwap(tokenA, tokenB) {
  if (!contract || !signer) return alert("Conectá la wallet primero.");

  const amountInValue = document.getElementById("amountIn").value;
  if (!amountInValue || isNaN(amountInValue) || Number(amountInValue) <= 0) {
    return alert("Ingresá una cantidad válida.");
  }

  try {
    const amountIn = ethers.parseUnits(amountInValue, 18);
    const reserveA = await contract.reserve(tokenA, tokenB);
    const reserveB = await contract.reserve(tokenB, tokenA);

    const amountOut = amountIn * BigInt(reserveB) / (BigInt(reserveA) + amountIn);
    const slippage = 1n; // 1%
    const amountOutMin = amountOut - (amountOut * slippage / 100n);

    const path = [tokenA, tokenB];
    const deadline = Math.floor(Date.now() / 1000) + 600;
    const to = await signer.getAddress();

    const tx = await contract.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    await tx.wait();

    alert("Swap realizado con éxito.");
    await updateBalances();
    await updatePrices();
  } catch (err) {
    console.error("Error durante el swap:", err);
    alert("Ocurrió un error en el intercambio.");
  }
}
