import
  NimQml,
  "."/[
    blockmodel, footermodel, epochmodel, peerlist, slotlist, nodemodel,
    poolmodel]

import
  std/[os, strutils],
  chronos, metrics,

  # Local modules
  ../beacon_chain/rpc/[beacon_rest_client, rest_utils],
  ../beacon_chain/ssz/merkleization,
  ../beacon_chain/spec/[datatypes, digest, crypto, helpers]

QtObject:
  type MainModel* = ref object of QObject
    app: QApplication
    blck: BlockModel
    footer: FooterModel
    client: RestClientRef
    peerList: PeerList
    epochModel: EpochModel
    nodeModel: NodeModel
    poolModel: PoolModel

    genesis: RestBeaconGenesis
    currentIndex: int

  proc delete*(self: MainModel) =
    self.QObject.delete
    self.blck.delete

  proc setup(self: MainModel) =
    self.QObject.setup
    self.blck.setup

  proc newMainModel*(app: QApplication): MainModel =
    let
      client = RestClientRef.new("http://127.0.0.1:8190").get()

    var
      headBlock = (waitFor client.getBlock(BlockIdent.init(BlockIdentType.Head))).data.data
      epoch = headBlock.message.slot.epoch
      genesis = (waitFor client.getBeaconGenesis()).data.data
      peerList = newPeerList(@[])

    headBlock.root = hash_tree_root(headBlock.message)

    let res = MainModel(
      app: app,
      blck: newBlockModel(headBlock, genesis.genesis_time),
      client: client,
      footer: newFooterModel(),
      peerList: peerList,
      epochModel: newEpochModel(client, epoch.int),
      nodeModel: newNodeModel(client),
      poolModel: newPoolModel(client),
      genesis: genesis,
    )
    res.setup()
    res

  proc onLoadTriggered(self: MainModel) {.slot.} =
    echo "Load Triggered"

  proc onSaveTriggered(self: MainModel) {.slot.} =
    echo "Save Triggered"

  proc onExitTriggered(self: MainModel) {.slot.} =
    self.app.quit

  proc updateFooter(self: MainModel) {.slot.} =
    let
      checkpoints = (waitFor self.client.getStateFinalityCheckpoints(StateIdent.init(StateIdentType.Head))).data.data
      head = (waitFor self.client.getBlockHeader(BlockIdent.init(BlockIdentType.Head))).data.data
      syncing = (waitFor self.client.getSyncingStatus()).data.data

    self.footer.finalized = $shortLog(checkpoints.finalized)
    self.footer.head = $shortLog(head.header.message.slot)
    self.footer.syncing = $syncing

  proc updateSlots(self: MainModel) {.slot.} =
    let
      slots = self.client.loadSlots(self.epochModel.epoch.Epoch)
    self.epochModel.setNewData(self.epochModel.epoch.int, slots)

  proc updatePeers(self: MainModel) {.slot.} =
    try:
      self.peerList.setNewData(waitFor(self.client.getPeers(@[], @[])).data.data)
    except CatchableError as exc:
      echo exc.msg

  proc getPeerList*(self: MainModel): QVariant {.slot.} =
    newQVariant(self.peerList)
  QtProperty[QVariant] peerList:
    read = getPeerList

  proc getFooter*(self: MainModel): QVariant {.slot.} =
    newQVariant(self.footer)
  QtProperty[QVariant] footer:
    read = getFooter

  proc getEpochModel*(self: MainModel): QVariant {.slot.} =
    newQVariant(self.epochModel)
  QtProperty[QVariant] epochModel:
    read = getEpochModel

  proc getBlck(self: MainModel): QVariant {.slot.} = newQVariant(self.blck)
  proc blckChanged*(self: MainModel, blck: QVariant) {.signal.}
  proc setBlck(self: MainModel, blck: SignedBeaconBlock) =
    self.blck.blck = blck
    self.blckChanged(newQVariant(self.blck))

  QtProperty[QVariant] blck:
    read = getBlck
    write = setBlck
    notify = blckChanged

  proc getCurrentIndex(self: MainModel): int {.slot.} = self.currentIndex
  proc currentIndexChanged*(self: MainModel, v: int) {.signal.}
  proc setCurrentIndex(self: MainModel, v: int) =
    self.currentIndex = v
    self.currentIndexChanged(v)

  QtProperty[int] currentIndex:
    read = getCurrentIndex
    write = setCurrentIndex
    notify = currentIndexChanged

  proc getNodeModel(self: MainModel): QVariant {.slot.} = newQVariant(self.nodeModel)
  QtProperty[QVariant] nodeModel:
    read = getNodeModel

  proc getPoolModel(self: MainModel): QVariant {.slot.} = newQVariant(self.poolModel)
  QtProperty[QVariant] poolModel:
    read = getPoolModel

  proc onLoadBlock(self: MainModel, root: string) {.slot.} =
    try:
      var blck = waitFor(self.client.getBlock(
        BlockIdent.decodeString(root).tryGet())).data.data
      blck.root = hash_tree_root(blck.message)
      self.setBlck(blck)
    except CatchableError as exc:
      echo exc.msg
    discard

  proc openUrl(self: MainModel, url: string) {.slot.} =
    if url.startsWith("block://"):
      self.onLoadBlock(url[8..^1])
      self.setCurrentIndex(1)
