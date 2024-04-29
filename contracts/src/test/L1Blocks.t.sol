// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {console} from "forge-std/console.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {L1Blocks} from "../L2/predeploys/L1Blocks.sol";
import {IL1Blocks} from "../L2/predeploys/IL1Blocks.sol";

contract L1BlocksTest is DSTestPlus {
    event UpdateTotalLimit(uint256 oldTotalLimit, uint256 newTotalLimit);

    uint256 private constant MIN_BASE_FEE_PER_BLOB_GAS = 1;

    uint256 private constant BLOB_BASE_FEE_UPDATE_FRACTION = 3338477;

    L1Blocks private b;

    function setUp() public {
        b = new L1Blocks();
    }

    // generated by the following golang code:
    // ```go
    // func main() {
    //   l1Client, _ := ethclient.Dial("https://eth.llamarpc.com")
    //   start, end := 12960000, 12960003
    //   fmt.Printf("bytes[] memory headers = new bytes[](%d);\n", end-start)
    //   fmt.Printf("bytes32[] memory hashes = new bytes32[](%d);\n", end-start)
    //   fmt.Printf("bytes32[] memory roots = new bytes32[](%d);\n", end-start)
    //   fmt.Printf("uint256[] memory timestamps = new uint256[](%d);\n", end-start)
    //   fmt.Printf("uint256[] memory baseFees = new uint256[](%d);\n", end-start)
    //   fmt.Printf("uint256[] memory blobBaseFees = new uint256[](%d);\n", end-start)
    //   fmt.Printf("bytes32[] memory parentBeaconRoots = new bytes32[](%d);\n", end-start)
    //   for n := start; n < end; n++ {
    //     header, _ := l1Client.HeaderByNumber(context.Background(), big.NewInt(int64(n)))
    //     data, _ := rlp.EncodeToBytes(header)
    //     fmt.Printf("headers[%d] = hex\"%s\";\n", n-start, common.Bytes2Hex(data))
    //     fmt.Printf("hashes[%d] = bytes32(%s);\n", n-start, header.Hash().String())
    //     fmt.Printf("roots[%d] = bytes32(%s);\n", n-start, header.Root.String())
    //     fmt.Printf("timestamps[%d] = %d;\n", n-start, header.Time)
    //     fmt.Printf("baseFees[%d] = %s;\n", n-start, header.BaseFee.String())
    //     fmt.Printf("blobBaseFees[%d] = _exp(MIN_BASE_FEE_PER_BLOB_GAS, %d, BLOB_BASE_FEE_UPDATE_FRACTION);\n", n-start, *header.ExcessBlobGas)
    //     fmt.Printf("parentBeaconRoots[%d] = bytes32(%s);\n", n-start, header.ParentBeaconRoot)
    //   }
    //   fmt.Printf("hevm.startPrank(address(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE));\n")
    //   fmt.Printf("for (uint256 i = 0; i < %d; i++) {\n", end-start)
    //   fmt.Printf("  b.setL1BlockHeader(headers[i]);\n")
    //   fmt.Printf("  assertEq(b.latestBlockNumber(), i + %d);\n", start)
    //   fmt.Printf("  assertEq(b.latestBlockHash(), hashes[i]);\n")
    //   fmt.Printf("  assertEq(b.latestStateRoot(), roots[i]);\n")
    //   fmt.Printf("  assertEq(b.latestBlockTimestamp(), timestamps[i]);\n")
    //   fmt.Printf("  assertEq(b.latestBaseFee(), baseFees[i]);\n")
    //   fmt.Printf("  assertEq(b.latestBlobBaseFee(), blobBaseFees[i]);\n")
    //   fmt.Printf("  assertEq(b.latestParentBeaconRoot(), parentBeaconRoots[i]);\n")
    //   fmt.Printf("  for (uint256 j = 0; j < i; j++) {\n")
    //   fmt.Printf("    assertEq(b.getBlockHash(j + %d), hashes[j]);\n", start)
    //   fmt.Printf("    assertEq(b.getStateRoot(j + %d), roots[j]);\n", start)
    //   fmt.Printf("    assertEq(b.getBlockTimestamp(j + %d), timestamps[j]);\n", start)
    //   fmt.Printf("    assertEq(b.getBaseFee(j + %d), baseFees[j]);\n", start)
    //   fmt.Printf("    assertEq(b.getBlobBaseFee(j + %d), blobBaseFees[j]);\n", start)
    //   fmt.Printf("    assertEq(b.getParentBeaconRoot(j + %d), parentBeaconRoots[j]);\n", start)
    //   fmt.Printf("  }\n")
    //   fmt.Printf("}\n")
    //   fmt.Printf("hevm.stopPrank();\n")
    // }
    // ```
    function testSetL1BlockHeaderPreLondon() external {
        bytes[] memory headers = new bytes[](3);
        bytes32[] memory hashes = new bytes32[](3);
        bytes32[] memory roots = new bytes32[](3);
        uint256[] memory timestamps = new uint256[](3);
        uint256[] memory baseFees = new uint256[](3);
        uint256[] memory blobBaseFees = new uint256[](3);
        bytes32[] memory parentBeaconRoots = new bytes32[](3);
        headers[
            0
        ] = hex"f90210a0a659a53bf981e33f7f3989b2a0a0490d5664f83090b19f01b7b426353b3825cba01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d493479499c85bb64564d9ef9a99621301f22c9993cb89e3a0608176ff31a7f73e18f803934eadc3ec2c5c633b1fddd2af9cbecc73e987f7c7a0d7335e0bef37fb782ede81b1439184ac1754ed83906b1c0bbfd2fbf6fe35d7cfa04a8d903e093905b851da8a7a44f149fb1f94b1720b45bf7b328493a5b3a94706b901004422e132c55703a1b242a440a0477b346192d421ac3042002683e569be2eabad0c1a5b6cb8559da0087359081269af190e47a58259d3b9dd8b14c8b7a3ec3a3ca818c0a48001291beec2f85e31407af40702e00c50767a6023535723c80543b05fc28501d3af12422500d9e8424e59e8b0cb163412480c66460805b203681c42c00c05a716c521b1d7c91d7b1127926599850fe97d200d7bee22054a311f1d24369f4709039029b0faa282949a5884061a853b07202248a35838673e5858090667bb2d468b066c43254093e821e27b241f8d4205862f3819a65610a2d4f066b223b1294bcc187104944f18c8a0960a8464ef683425528a6ac05c8a9173c6f965871b4f7096102a7983c5c10083e51ae983e50a8084610acf218f626565706f6f6c2e6f72675f362029a0e9ee3a483b039bfd767c8b1e46bcd167b99695e39cde065ad0d3ab44ac95c83c880080918a281c1f0a";
        hashes[0] = bytes32(0xd09bfe09aff80dd4f0eebedea3088d0409ccd3b991b4585121b29d8477f3e467);
        roots[0] = bytes32(0x608176ff31a7f73e18f803934eadc3ec2c5c633b1fddd2af9cbecc73e987f7c7);
        timestamps[0] = 1628098337;
        baseFees[0] = 0;
        blobBaseFees[0] = 0;
        parentBeaconRoots[0] = bytes32(0);
        headers[
            1
        ] = hex"f90215a0d09bfe09aff80dd4f0eebedea3088d0409ccd3b991b4585121b29d8477f3e467a059008249738cbaa0af10792f17ae2ca03029b746a07818f1da79e2a2edf72d7e94ea674fdde714fd979de3edf0f56aa9716b898ec8a0c41a6fddad482606f94a052573a9a20b14ceab6937bb28154044b97235d8d1e7a0e9967a894e9baa3a2d220a500424329c1b8e983ebf85bce9e21eff9904558c3aa0206a323f668c3a21bdd5086e444a038599f170ca96735f19fb573dd81de269f5b90100b0a2014241ea1a91309c3ac887a3fad7208e31085ad0a300b019555cc4ba8364480f115a1042408a4028594808001920420788c96a0aa90002488b118a6caa194a0ac42f690f990be82722793724f1a50202248c8540000020422dc1fb495d40906780555b2a85600f05504c000609b4f0400d60a02d4c426a6d95b4810811ac18118a710e5c0a3082e8204f81224e8c344685ab1961e4ec3ef120da0891691002bc258a11e1295388200a93803a301992243a9784e8408b01333adb5c5e5a4460b1204261c207c5b9908219c1fa17740a64020e278b7a12ea4573c6b856308109bc2c232f0cf040084714e8d402088002e1340121c1c04026c4e88600929631871b3441257a1a5183c5c10183e4e1a483e4a68584610acf769465746865726d696e652d617369612d6561737432a08b64636aa94ba0f721183056507856223a51ba50ee7ee7d96d0f3404440584e4882c112efdc272cb79";
        hashes[1] = bytes32(0xe2aeb185c6893525d3d5727d9ff69cec11892c4a680323794ef77ef6a0dfd0f1);
        roots[1] = bytes32(0xc41a6fddad482606f94a052573a9a20b14ceab6937bb28154044b97235d8d1e7);
        timestamps[1] = 1628098422;
        baseFees[1] = 0;
        blobBaseFees[1] = 0;
        parentBeaconRoots[1] = bytes32(0);
        headers[
            2
        ] = hex"f90217a0e2aeb185c6893525d3d5727d9ff69cec11892c4a680323794ef77ef6a0dfd0f1a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d4934794ea674fdde714fd979de3edf0f56aa9716b898ec8a08539d6baa1a5d68251245df40bee061b7ab582f7ac5ff889c63af5a65af5ae97a07b0b455b3389cc66f9df93a45c4457f34a4b51acb428ce4cabf25438dbaff6fba0986257aee973560f72930022ac04f5dd45da542ebf16ce7d35062a18505940eeb9010033fa62a647fa46c99f937ab7c2633e65702ec2a1a810045c8da9243dacce4e26beec994a38d985e1d416599129054d79b28788358b47e917c7371aa106a881044193c618d3259b2bdebe33bdfc097570148b7c78186303050cd0bc468eed3dc19ff38cf5c2bb860219cc164c3014bdf4f8cfd9248f001658ca77489ce17913405ab6c58bce2667dcf2df01582d427f650625b225332e45ca06604a7c51b1c93087de445abbefe3cb3ee2629a9e329cfad3b6221f30e6f2f093362f971a4858727a1dbd33e1000d48230a0af16cf07d960e1faa0344283859eaf1f3a248d17185a5b82d8d4c0610013080568e9e834a8520c124f6e16f02455e3deab5040a7ab9871b3b2e35c378d783c5c10283e4a86d83e4609984610acf7c9665746865726d696e652d6575726f70652d7765737433a0f52495bbbc91b115ef0a1c39d2a3b153e1b2d228b6088f16bb599518c2138f6488dd4e2aa23050b292";
        hashes[2] = bytes32(0x5bf8d6769fa2add2aec95053e458d2b338bf12ee6dea384b2355f5586cf437fb);
        roots[2] = bytes32(0x8539d6baa1a5d68251245df40bee061b7ab582f7ac5ff889c63af5a65af5ae97);
        timestamps[2] = 1628098428;
        baseFees[2] = 0;
        blobBaseFees[2] = 0;
        parentBeaconRoots[2] = bytes32(0);
        hevm.startPrank(address(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE));
        for (uint256 i = 0; i < 3; i++) {
            b.setL1BlockHeader(headers[i]);
            assertEq(b.latestBlockNumber(), i + 12960000);
            assertEq(b.latestBlockHash(), hashes[i]);
            assertEq(b.latestStateRoot(), roots[i]);
            assertEq(b.latestBlockTimestamp(), timestamps[i]);
            assertEq(b.latestBaseFee(), baseFees[i]);
            assertEq(b.latestBlobBaseFee(), blobBaseFees[i]);
            assertEq(b.latestParentBeaconRoot(), parentBeaconRoots[i]);
            for (uint256 j = 0; j < i; j++) {
                assertEq(b.getBlockHash(j + 12960000), hashes[j]);
                assertEq(b.getStateRoot(j + 12960000), roots[j]);
                assertEq(b.getBlockTimestamp(j + 12960000), timestamps[j]);
                assertEq(b.getBaseFee(j + 12960000), baseFees[j]);
                assertEq(b.getBlobBaseFee(j + 12960000), blobBaseFees[j]);
                assertEq(b.getParentBeaconRoot(j + 12960000), parentBeaconRoots[j]);
            }
        }
        hevm.stopPrank();
    }

    function testSetL1BlockHeaderLondon() external {
        bytes[] memory headers = new bytes[](3);
        bytes32[] memory hashes = new bytes32[](3);
        bytes32[] memory roots = new bytes32[](3);
        uint256[] memory timestamps = new uint256[](3);
        uint256[] memory baseFees = new uint256[](3);
        uint256[] memory blobBaseFees = new uint256[](3);
        bytes32[] memory parentBeaconRoots = new bytes32[](3);
        headers[
            0
        ] = hex"f9021fa03de6bb3849a138e6ab0b83a3a00dc7433f1e83f7fd488e4bba78f2fe2631a633a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347947777788200b672a42421017f65ede4fc759564c8a041cf6e8e60fd087d2b00360dc29e5bfb21959bce1f4c242fd1ad7c4da968eb87a0dfcb68d3a3c41096f4a77569db7956e0a0e750fad185948e54789ea0e51779cba08a8865cd785e2e9dfce7da83aca010b10b9af2abbd367114b236f149534c821db9010024e74ad77d9a2b27bdb8f6d6f7f1cffdd8cfb47fdebd433f011f7dfcfbb7db638fadd5ff66ed134ede2879ce61149797fbcdf7b74f6b7de153ec61bdaffeeb7b59c3ed771a2fe9eaed8ac70e335e63ff2bfe239eaff8f94ca642fdf7ee5537965be99a440f53d2ce057dbf9932be9a7b9a82ffdffe4eeee1a66c4cfb99fe4540fbff936f97dde9f6bfd9f8cefda2fc174d23dfdb7d6f7dfef5f754fe6a7eec92efdbff779b5feff3beafebd7fd6e973afebe4f5d86f3aafb1f73bf1e1d0cdd796d89827edeffe8fb6ae6d7bf639ec5f5ff4c32f31f6b525b676c7cdf5e5c75bfd5b7bd1928b6f43aac7fa0f6336576e5f7b7dfb9e8ebbe6f6efe2f9dfe8b3f56871b81c1fe05b21883c5d4888401ca35428401ca262984610bdaa69768747470733a2f2f7777772e6b7279707465782e6f7267a09620b46a81a4795cf4449d48e3270419f58b09293a5421205f88179b563f815a88b223da049adf2216843b9aca00";
        hashes[0] = bytes32(0x9b83c12c69edb74f6c8dd5d052765c1adf940e320bd1291696e6fa07829eee71);
        roots[0] = bytes32(0x41cf6e8e60fd087d2b00360dc29e5bfb21959bce1f4c242fd1ad7c4da968eb87);
        timestamps[0] = 1628166822;
        baseFees[0] = 1000000000;
        blobBaseFees[0] = 0;
        parentBeaconRoots[0] = bytes32(0);
        headers[
            1
        ] = hex"f9021aa09b83c12c69edb74f6c8dd5d052765c1adf940e320bd1291696e6fa07829eee71a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d4934794829bd824b016326a401d083b33d092293333a830a00180d59eb0855ef6dbca806fbe81491bea252ab2e0d3a8bb8786326d598e3cd9a003c97f958cc4db3cc60def5ce1e83aaf1490837f5f57c529a6ccffef0d201edba02335850563dbf51f65a37508f2fdd9da1780f70cfa46734107a2e86a9fde46d7b9010074adf8cfdd0a1ddf12f3d6d5bbd79cab73a19b6986fc007932d9acffafebb747debf512456c87e9afffa5f40fd21ad403b97f3b38e86e9e9db62433eb2b6f8547ad677fdab07f1adcb83686fb37db9ea7acb113f0d74b397324d9cfbf8f33cb3dbfb0d256bcbdaf608dd7b1ac168ee40e322b69bf675a6f4fbbbbe72dccbdd88fab28e7d94685c34bffc9bd1ff98ef777af7ff9793de951d336a1b75acbc7f11ce9dac7e9942ab6a363b4fbebbc3d738dbee5a993fa7c87adce26cbeddfdfcf4d59bba977fb7514a3da550c0b21f399e8bf56778c7dfdcfeeb2457abef1fe63eaf38ecbabdae6c237afd34378163feb6ccdb42f56782cd474bdf9ee9fadb94b4871b81c23e05b21883c5d4898401c9c2b68401c9897884610bdab392e4b883e5bda9e7a59ee4bb99e9b1bc030521a0cb3166ebb1888430069b769145b20ba5e3a55f32fd2fa39f0ebdc08d60b4557e880956e895d988798e84430da58e";
        hashes[1] = bytes32(0xa32d159805750cbe428b799a49b85dcb2300f61d806786f317260e721727d162);
        roots[1] = bytes32(0x0180d59eb0855ef6dbca806fbe81491bea252ab2e0d3a8bb8786326d598e3cd9);
        timestamps[1] = 1628166835;
        baseFees[1] = 1124967822;
        blobBaseFees[1] = 0;
        parentBeaconRoots[1] = bytes32(0);
        headers[
            2
        ] = hex"f90218a0a32d159805750cbe428b799a49b85dcb2300f61d806786f317260e721727d162a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d493479401ca8a0ba4a80d12a8fb6e3655688f57b16608cfa04417fa3fa0483322e9b19d2a2659c8e0a7e7fd2cb68db0419a955fdcad267c37a02d062a3463427b8297819abc1a344fc72412aba542f61b413171076b4de8e8b7a0e9444c1d62f922849f2e00fb71cf1aeea2c3410c017f38ee13c29afc12c66265b9010067bd1d7f3c5a2b5d15bcb4ef8b95feafbfdadad8fcec57bb56fb3f72e7dbd9fe86b34f4a7c0b76e6b4c7730583635d13efdef9bfcf3659edb9592eb46cadfa7a5d57f9c5eb24ede68f87329edbc37ebb57e842e68f6bea1df34cbed5f307b5917fa5e77463fea6aae53f543f5092fad9df76d6bbdf48edec8bb17cd3f1438e53dbcc3635647abff6d3efacdbed35bdae48b2dfe537fcd6dd2fa81572a6fecabbffd847d71e8beb0f5e03be90894facfc13e82bcdb7a735673bbff56a7fef6bd53f5eaf57bd8bd9f72d559e7f7fde836c6fabaf55d60ece5923b49dd7687e2ca2f2f8b45a969e652afd557e7745dbdd778dbae221f927fd5d874d9f7ec9ba1a60871b7e5245bdf16283c5d48a8401c950478401c9018784610bdac690706f6f6c2e62696e616e63652e636f6da002e216ecd9bf49349517d646a3f591b15b3159ed9222260033cc7b4645c7ce638853b623b975c42d06844b6d419d";
        hashes[2] = bytes32(0xfcb92039b16c0075d4c6c57cb55ba8c661914325bb7626416f48e9aa735ce2b5);
        roots[2] = bytes32(0x4417fa3fa0483322e9b19d2a2659c8e0a7e7fd2cb68db0419a955fdcad267c37);
        timestamps[2] = 1628166854;
        baseFees[2] = 1265451421;
        blobBaseFees[2] = 0;
        parentBeaconRoots[2] = bytes32(0);
        hevm.startPrank(address(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE));
        for (uint256 i = 0; i < 3; i++) {
            b.setL1BlockHeader(headers[i]);
            assertEq(b.latestBlockNumber(), i + 12965000);
            assertEq(b.latestBlockHash(), hashes[i]);
            assertEq(b.latestStateRoot(), roots[i]);
            assertEq(b.latestBlockTimestamp(), timestamps[i]);
            assertEq(b.latestBaseFee(), baseFees[i]);
            assertEq(b.latestBlobBaseFee(), blobBaseFees[i]);
            assertEq(b.latestParentBeaconRoot(), parentBeaconRoots[i]);
            for (uint256 j = 0; j < i; j++) {
                assertEq(b.getBlockHash(j + 12965000), hashes[j]);
                assertEq(b.getStateRoot(j + 12965000), roots[j]);
                assertEq(b.getBlockTimestamp(j + 12965000), timestamps[j]);
                assertEq(b.getBaseFee(j + 12965000), baseFees[j]);
                assertEq(b.getBlobBaseFee(j + 12965000), blobBaseFees[j]);
                assertEq(b.getParentBeaconRoot(j + 12965000), parentBeaconRoots[j]);
            }
        }
        hevm.stopPrank();
    }

    function testSetL1BlockHeaderCancun() external {
        bytes[] memory headers = new bytes[](3);
        bytes32[] memory hashes = new bytes32[](3);
        bytes32[] memory roots = new bytes32[](3);
        uint256[] memory timestamps = new uint256[](3);
        uint256[] memory baseFees = new uint256[](3);
        uint256[] memory blobBaseFees = new uint256[](3);
        bytes32[] memory parentBeaconRoots = new bytes32[](3);
        headers[
            0
        ] = hex"f9025fa0db672c41cfd47c84ddb478ffde5a09b76964f77dceca0e62bdf719c965d73e7fa01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d4934794dae56d85ff707b3d19427f23d8b03b7b76da1006a0bd33ab68095087d81beb810b3f5d0b16050b3f798ae3978e440bab048dd78992a020cbdd2cd6113eb72dade6be7ec18fe6a7167a8a0af912a2171af909a8cda9f6a059c3691e83e0ddeafeedd07f5e30850cc6c963e85327aa1201fbe1f731ff3dbcb901000021000000000001080801008000320000000060000000000005000080c200040000100000006002440409000000010402011000890200000a201000042800440442148c0100208408004009012000200000040801644808800000600029068004012001020000002510000000020900c8122010020284000080021006000101000000401810621c0040000000001010000004800100404808000640255000002201000010002000000040c0000000000400a004000c0000884000304e00202400100402000000004204000004041008005600001000001000000003015030120012280000022020910040429204408020009000000010120000400000000400808401286d1b8401c9c380832830cd8465f1b05799d883010d0e846765746888676f312e32312e37856c696e7578a02617b147c1b3cf43a28d08d508ab2d8860c6cf40da58837676cfaaf4f9e07f62880000000000000000850e6ca77a30a06c119891018ed3a43d04197a8eb94d85f287304b8ace21b08e9f68cbd2f8de618080a0b35bb80bc5f4e3d8f19b62f6274add24dca334db242546c3024403027aaf6412";
        hashes[0] = bytes32(0xf8e2f40d98fe5862bc947c8c83d34799c50fb344d7445d020a8a946d891b62ee);
        roots[0] = bytes32(0xbd33ab68095087d81beb810b3f5d0b16050b3f798ae3978e440bab048dd78992);
        timestamps[0] = 1710338135;
        baseFees[0] = 61952457264;
        blobBaseFees[0] = _exp(MIN_BASE_FEE_PER_BLOB_GAS, 0, BLOB_BASE_FEE_UPDATE_FRACTION);
        parentBeaconRoots[0] = bytes32(0xb35bb80bc5f4e3d8f19b62f6274add24dca334db242546c3024403027aaf6412);
        headers[
            1
        ] = hex"f90255a0f8e2f40d98fe5862bc947c8c83d34799c50fb344d7445d020a8a946d891b62eea01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347948186b214a917fb4922eb984fb80cfafa30ee8810a0e4ca273952459efe6fddc9b1ed4d3fce53a85a66103985e1af9e8a120115afe4a0fb16519bfe18e4d8380778053ace3010a4357c1bdb1c9dfd8feda8078be23fc4a08a1616cfb1d886e9c3183cba4b19e16b80d4a38f4eb4f996a196c143a4092766b90100142b546af340118b1004096cd426d6a50059e2a04672400240850043c408202c141ce30299c053a076385b69443203545203ac298c2221c842c6919b34ae78a91c0755e824512b0a280be24d910cb1ed6009c05b00f658544422544c976475909fa6e2248aa30c009245f0400b085d601d7708730004240a1e7966ba45081062080997d14740708b214617d1014200261d83088349819e28662203e386700400aac239f268a160b2011148e69211078086229c050560030aa9a5049b80c8e055afd12593054a854569011302900e08780c663283770b42543409630683f46251de58a9290112401c2c0c762044211241c72150a2081f8063020882d00e02e580808401286d1c8401c9c38083eab9738465f1b0638f6c6f6b696275696c6465722e78797aa071e00db543e3e4b91eb392d81890499926275490e7f592f76f7428e2997765a6880000000000000000850cf01fc701a0804fd42384c45b31d07052e161d33a2e3d47d1b64dc72cc32d76c3905ff35d328080a0a471c7622a976313a61e01b01212dcea6acd71f351618734928dcabe4aba62fe";
        hashes[1] = bytes32(0x92d191c33229bf530e0a74913d604dc7c7f8d6dfd5d73f90e76f7a2e5d19c263);
        roots[1] = bytes32(0xe4ca273952459efe6fddc9b1ed4d3fce53a85a66103985e1af9e8a120115afe4);
        timestamps[1] = 1710338147;
        baseFees[1] = 55568221953;
        blobBaseFees[1] = _exp(MIN_BASE_FEE_PER_BLOB_GAS, 0, BLOB_BASE_FEE_UPDATE_FRACTION);
        parentBeaconRoots[1] = bytes32(0xa471c7622a976313a61e01b01212dcea6acd71f351618734928dcabe4aba62fe);
        headers[
            2
        ] = hex"f90254a092d191c33229bf530e0a74913d604dc7c7f8d6dfd5d73f90e76f7a2e5d19c263a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d493479488c6c46ebf353a52bdbab708c23d0c81daa8134aa08261a2a412930bbeade873726535a993723369615e2abad295da9a5398082292a02605fd9b61c93f7f28b1fc11c8672df88bca49d65bab63b6c1af9fe82b7f76aca0e549cd4fb39961fd40eb76924713dc631e2431681aadd617b208f23f0bc0f208b901001065c50c7d041102110c2820fc84213025021620005494934803116424000555000440cb001042650012d3008f12a100072188319d3f214801a6c048006a09110801c08818480a8c1830488c8a0600600880800d80550a91011013c4c1304182102272008224142821004c0008003a90d0220a11001b0c2d320801da062a2002240783462681b028026915290a08902008180a01010080186402a040053102002e810882041364612898008c308904c10510ac020c0851022801d6da00242558ab8c0402424890bb07000001001616000802431230820310260159061222274042d2a00005b0a2124384010058246e0400021083059c0052422a2a314c0b2c0d808401286d1d8401c9c380836d30ee8465f1b06f8b6a6574626c64722e78797aa057dc6b69f4e021c07813699c031bf61baad4f468040398aa8cf891d6da85d730880000000000000000850cfab14a38a017ce08097a888dc1ad4161a9dffc38bca83d22a0da5b358d13ec2945b59660d58302000080a0e8d226954b651474710dc4c1b32331d9a3074a3e61972c56b361c0df4c3594c7";
        hashes[2] = bytes32(0xa2917e0758c98640d868182838c93bb12f0d07b6b17efe6b62d9df42c7643791);
        roots[2] = bytes32(0x8261a2a412930bbeade873726535a993723369615e2abad295da9a5398082292);
        timestamps[2] = 1710338159;
        baseFees[2] = 55745530424;
        blobBaseFees[2] = _exp(MIN_BASE_FEE_PER_BLOB_GAS, 0, BLOB_BASE_FEE_UPDATE_FRACTION);
        parentBeaconRoots[2] = bytes32(0xe8d226954b651474710dc4c1b32331d9a3074a3e61972c56b361c0df4c3594c7);
        hevm.startPrank(address(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE));
        for (uint256 i = 0; i < 3; i++) {
            b.setL1BlockHeader(headers[i]);
            assertEq(b.latestBlockNumber(), i + 19426587);
            assertEq(b.latestBlockHash(), hashes[i]);
            assertEq(b.latestStateRoot(), roots[i]);
            assertEq(b.latestBlockTimestamp(), timestamps[i]);
            assertEq(b.latestBaseFee(), baseFees[i]);
            assertEq(b.latestBlobBaseFee(), blobBaseFees[i]);
            assertEq(b.latestParentBeaconRoot(), parentBeaconRoots[i]);
            for (uint256 j = 0; j < i; j++) {
                assertEq(b.getBlockHash(j + 19426587), hashes[j]);
                assertEq(b.getStateRoot(j + 19426587), roots[j]);
                assertEq(b.getBlockTimestamp(j + 19426587), timestamps[j]);
                assertEq(b.getBaseFee(j + 19426587), baseFees[j]);
                assertEq(b.getBlobBaseFee(j + 19426587), blobBaseFees[j]);
                assertEq(b.getParentBeaconRoot(j + 19426587), parentBeaconRoots[j]);
            }
        }
        hevm.stopPrank();
    }

    /// @dev Approximates factor * e ** (numerator / denominator) using Taylor expansion:
    /// based on `fake_exponential` in https://eips.ethereum.org/EIPS/eip-4844
    function _exp(uint256 factor, uint256 numerator, uint256 denominator) private pure returns (uint256) {
        uint256 output;
        uint256 numerator_accum = factor * denominator;
        for (uint256 i = 1; numerator_accum > 0; i++) {
            output += numerator_accum;
            numerator_accum = (numerator_accum * numerator) / (denominator * i);
        }
        return output / denominator;
    }
}
