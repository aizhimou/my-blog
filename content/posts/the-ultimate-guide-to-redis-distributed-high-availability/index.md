---
title: "Redis 分布式高可用终极指南"
date: "2020-08-21"
summary: "本文试图将 redis 分布式和集群方案从概念理解到技术选型到搭建使的整个过程用最简单的语言讲述清楚。"
toc: true
readTime: true
autonumber: false
math: true
tags: ["database", "redis"]
showTags: true
hideBackToTop: false
---

最近项目上需要用到 redis 高可用方案，遂上网找了一些资料学习，但是网上关于 redis 高可用的几种实现方式或口径不一，或含糊不清，或缺斤少两。经历了多方资料学习和实际验证，本文试图将 redis 分布式和集群方案从概念理解到技术选型到搭建使的整个过程用最简单的语言讲述清楚。

## 分布式与集群

下文会涉及到大量的分布式和集群术语，这里我们先来复习一下集群和分布式的概念，加深一下理解。

目前的项目很少会采用单机架构了，一是因为单机性能有限，二是因为单机服务一旦故障整个系统就无法继续提供服务了。所以目前集群和分布式的架构使用得很广泛，主要就是为了解决上述两个问题，一个性能问题，一个故障问题，**通过分布式架构解决性能（高并发）问题，通过集群架构解决故障服务（高可用）问题。**

### 分布式架构

> 分布式：一个业务分拆多个子业务，部署在不同的服务器上

网上很多文章把分布式架构说得很复杂，但都没有切中关键，其实理解起来很简单，所有的计算机系统都是为业务服务的，将同一个业务拆分成多个子业务，各个子业务部署在不同的服务器上，这就是分布式架构，通过将业务拆细，为不同的子业务配置不同性能的服务器，提高整个系统的性能。*我个人认为目前很火的微服务概念其实本质上就是分布式。*

按照类型大致可以分为两种：**分布式计算**和**分布式存储**。

分布式计算很好理解，就是将大量计算任务分配到多个计算单元上以提高总计算性能。例如暴力破解某个密码需要遍历某个字符组合10万次，假设一台计算机需要10分钟，那么10台计算机同时遍历，每台遍历1万次，最后将结果汇总，那么就只需要1分钟。这10台计算机组合起来就是一个分布式计算系统，这里的业务就是计算。

同理，分布式储存也很好理解，就是将大量数据分配到多个储存单元上以提高总存储量。例如100ZB的数据一个储存单元放不下，那就拆成100份，每个储存单元存1份，那么这100个存储单元组合起来就是一个分布式储存系统，这里的业务就是存储。目前主流的关系型数据库都有比较成熟的分布式存储方案，如 MySQL 的 MySQL Fabric、MyCat 等，Oracle Database 有Oracle Sharding 等。Redis 作为流行的非关系型数据库，由于是内存数据库，理论上一般不会在 Redis 中存放太多的数据，但是在某些特殊情况下还是会有储存空间不够的情况，或者需要预防储存空间不够的情况发生，这个时候就需要 Redis 分布式架构了。

例如某集团下有很多的子公司，每个子公司都有多套 IT 系统，其中很多 IT 系统都是需要使用 Redis 的，集团为了统一管理，搭建了一套中央 Redis 系统，要求所有子公司下的 IT 系统统一使用集团的中央 Redis 库，这个时候即使当前储存容量够用，但是为了应对后期发展就必须使用到分布式储存，因为分布式架构理论上都支持无限水平拓展。

### 集群架构

> 集群：同一个业务，部署在多个服务器上

集群同样也非常好理解，就是在多个服务器上部署同一个业务，这样可以起到两个作用：

1. 分散每台服务器的压力
2. 任意一台或者几台服务器宕机也不会影响整个系统

例如一个典型的 Web 集群服务架构图如下：

![一个典型的 Web 集群架构图](https://picr.zz.ac/09XjF0W0wYZhRazi2_Q2ozKcZpwEa5U3Z2-WJPo4PuM=)

这里三个 Web Server 服务器实际上都是运行着同一套业务，但是三台服务器就可以显著分散单台服务器压力，并且任意一台宕机也不会导致无法提供服务。

### 分布式与集群的关系

分布式和集群区别很好理解，用下面一张图表示：

![分布式与集群的区别](https://picr.zz.ac/BSOhlw6rICt7FT86F1YQe3WyX5_qRnFnrxqqtw4yAdU=)

**需要注意的是分布式不一定能用上，但是集群一般都是需要的。因为不是所有系统都需要应对高并发场景，但高可用是一个系统能够长期稳定运行基本保障。因此用到分布式架构的系统基本上都会用到集群，而用集群架构的系统却不一定会用到分布式。**

## Redis 部署指南

### 单节点方案：Redis Standalone

#### 原理简介

这是最简单的 redis 部署方案，所有数据存储和读写操作都在同一个 redis 服务上。

这种方式优点很明显：部署简单，无论是部署成本还是运维成本都很低，本地测试时最常见也是最方便的方式。

但同时缺点也很明显：不能实现高可用，也不能应对高并发场景，也无法轻易水平拓展，数据储存量很容易见顶。

#### 部署实例

单节点模式的部署是最简单的，一下是 Linux 系统下部署单节点 redis 的方法：

``` shell
# 下载 Redis 二进制安装包：
wget http://download.redis.io/releases/redis-5.0.4.tar.gz
# 解压二进制包
tar –zxvf redis-5.0.4.tar.gz
# 进入解压文件夹并编译二进制文件
cd redis-5.0.4
make
# 安装
cd src
make test
make install
```

在 make install 和 make test 的时候可能会遇到下面这个问题：

``` shell
You need tcl 8.5 or newer in order to run the Redis test
make: *** [test] Error 1
```

这是因为系统中的 TCL 语言版本太低，TCL 语言是一种工具脚本语言，在安装 Redis 的过程中 make test 命令需要用到这个脚本语言，这个时候我们需要升级一下系统中的 TCL 版本：

``` shell
# 下载一个高于 8.5 版本的 TCL 安装包，比如 8.6.8
wget http://downloads.sourceforge.net/tcl/tcl8.6.8-src.tar.gz
# 解压
tar -zxvf tcl8.6.8-src.tar.gz  -C /usr/local/  
# 切换到解压后的源码目录
cd  /usr/local/tcl8.6.8/unix/
# 编译和安装
sudo ./configure  
sudo make  
sudo make install
```

升级 TCL 到 8.5 版本以后，继续执行之前报错的语句，完成 Redis 的安装，安装完成后用 `redis-server -v` 验证安装是否成功，若成功输出如下版本信息则代表安装成功：

``` shell
Redis server v=5.0.4
```

安装成功就可以直接运行了，但是默认配置下是不支持后台运行的，观点命令窗口就会结束 redis 进程，这显然是不行的。所以我们再简单改一下 redis 的配置，让其能够直接后台运行。

```shell
# 进入到 redis 的安装目录，编辑 redis.conf
vim /usr/redis/redis-5.0.4/redis.conf
# 将 daemonize no 修改成 daemonize yes （使 redis 服务可以在后台运行）

# 在指定配置下运行redis服务
/usr/local/bin/redis-server /usr/redis/redis-5.0.4/redis.conf 
# 查看redis运行情况
ps -ef | grep redis

# 输出
app	  21794   1  0 Jan28 ?  03:31:25 ./redis-server *:6379
```

可以看到 redis 在默认的 6379 端口下运行，配置文件中还有一些可以调整的地方，这里就不一一列举了。

那么单节点模式 redis 服务就部署完成了

### Redis 高可用方案：Redis Sentinel

#### 原理简介

**Redis Sentinel 是 Redis 官方推荐的高可用性(HA)解决方案，这是生产环境中最实用也是最常用的方案。**

这里涉及到另一个概念：master-slaver（主从模式）。很好理解，就是常用的主备模式，例如 nginx 的主备模式。一个主 redis 节点可以配置多个从节点，当主节点挂掉时，从节点自动顶上代替主节点，这样就可以有效的避免一个节点挂掉导致整个系统挂掉的问题，实现 redis 服务的高可用。如下图：

![master-slaver](https://picr.zz.ac/eoVtZ7sDWFu4c-Rwmcw46gBcy7ZiOfGGNGK8Xej3Oic=)

但是这个方案需要解决两个基本问题：

1. 如何提前判断各个节点（尤其是主节点）的运行健康状况？
2. 当主节点宕机的时候如何从多个从节点中选出一个作为新的主节点并实现自动切换？

这时 Redis Sentinel 应运而生，它主要有以下三个特点：

- **监控（Monitoring**）：Sentinel 会不断地检查你的主服务器和从服务器是否运作正常。
- **提醒（Notification）**：当被监控的某个 Redis 服务器出现问题时，Sentinel 可以通过 API 向管理员或者其他应用程序发送通知。
- **自动故障迁移（Automatic failover）**：当一个主服务器不能正常工作时，Sentinel 会开始一次自动故障迁移操作， 它会将失效主服务器的其中一个从服务器升级为新的主服务器，并让失效主服务器的其他从服务器改为复制新的主服务器； 当客户端试图连接失效的主服务器时， 集群也会向客户端返回新主服务器的地址，使得集群可以使用新主服务器代替失效服务器。

总结来说就是 sentinel 可以监控一个或者多个 master-slaver 集群，定时对每个节点进行健康检查，可以通过 API 发送通知，并自动进行故障转移。这时r redis 结构就变成了

**使用了 redis sentinel 之后客户端不再直接连接 redis 节点获取服务，而是使用 sentinel 代理获取 redis 服务**，类似 Nginx 的代理模式。那么这里又有一个新问题，就是**如果 sentinel 宕机了，那么客户端就找不到 redis 服务了，所以 sentinel 本身也是需要支持高可用。**

**好在sentinel 本身也支持集群部署，并且各个 sentinel 之间支持自动监控，如此一来 redis 主从服务和 sentinel 服务都可以支持高可用。**预期结构如下：

![redis sentinel集群](https://picr.zz.ac/ILXAQBhefSj4vcXnlxGveTytvRerrnrXB2YaJ_1-lR8=)

#### 部署实例

##### master-slaver 一主二从

那么下面我们就来实操一下，以下过程大部分参考 redis 官方 [Redis Sentinel 文档](<https://redis.io/topics/sentinel#redis-sentinel-documentation>)。

安装 redis 就不重复了，和单机 redis 一样。

redis 解压后，redis home 目录下有 redis 配置的样例文件，我们不直接在此文件上就行修改，在redis home目录下新建文件夹 master-slave ，将配置文件都放于此目录下，下面是三个 redis 节点配置的关键部分

- master 配置文件：redis-6379.conf 

```shell
port 6379
daemonize yes
logfile "6379.log"
dbfilename "dump-6379.rdb"
dir "/opt/soft/redis/data"
```

- slave-1 配置文件：redis-6380.conf

```shell
port 6380
daemonize yes
logfile "6380.log"
dbfilename "dump-6380.rdb"
dir "/opt/soft/redis/data"
# 关键配置：将这个 redis 指定为某个第一个 redis 的 slaver
slaveof 127.0.0.1 6379
```

- slave-2 配置文件：redis-6381.conf

```shell
port 6381
daemonize yes
logfile "6381.log"
dbfilename "dump-6381.rdb"
dir "/opt/soft/redis/data"
# 关键配置：将这个 redis 指定为某个第一个 redis 的 slaver
slaveof 127.0.0.1 6379
```

分别启动这三个 redis 服务，启动过程就不罗嗦了，和分别启动三个单机 redis 是一样的，分别指定三个配置文件即可。启动后如下图所示：

![image](https://picr.zz.ac/dErcqhFEelV10AZR1gAiGHw-h4YjQzuAnXYqvxMnIlc=)

6379、6380、6381 端口分别在运行一个 redis-server。

接下来查看这三个 redis-server 之间的关系：连接到主 redis 上用 `info replication`即可查看

![image](https://picr.zz.ac/rn30SawRbNMPd0R7XxhQc9k24WOHctw3M7igbLh2E2I=)

可以看到当前连接的 redis 服务为 master 角色，下面有两个 slaver，IP 和端口都能看到。

**这样我们就顺利的完成了 一主二从 redis 环境的搭建，下面开始搭建 sentinel 集群。**

##### sentinel 集群

sentinel 本质上是一个特殊的 redis，大部分配置和普通的 redis 没有什么区别，主要区别在于端口和其哨兵监控设置，下面是三个典型的 sentinel 配置文件中的关键内容：

- sentinel-26379.conf

```shell
#设置 sentinel 工作端口
port 26379
#后台运行 
daemonize yes
#日志文件名称
logfile "26379.log"
#设置当前 sentinel 监控的 redis ip 和 端口
sentinel monitor mymaster 127.0.0.1 6379 2
#设置判断 redis 节点宕机时间
sentinel down-after-milliseconds mymaster 60000
#设置自动故障转移超时
sentinel failover-timeout mymaster 180000
#设置同时故障转移个数
sentinel parallel-syncs mymaster 1
```

- sentinel-26380.conf

```shell
#设置 sentinel 工作端口
port 26380
#后台运行 
daemonize yes
#日志文件名称
logfile "26380.log"
#设置当前 sentinel 监控的 redis ip 和 端口
sentinel monitor mymaster 127.0.0.1 6379 2
#设置判断 redis 节点宕机时间
sentinel down-after-milliseconds mymaster 60000
#设置自动故障转移超时
sentinel failover-timeout mymaster 180000
#设置同时故障转移个数
sentinel parallel-syncs mymaster 1
```

- sentinel-26381.conf

```shell
#设置 sentinel 工作端口
port 26391
#后台运行 
daemonize yes
#日志文件名称
logfile "26381.log"
#设置当前 sentinel 监控的 redis ip 和 端口
sentinel monitor mymaster 127.0.0.1 6379 2
#设置判断 redis 节点宕机时间
sentinel down-after-milliseconds mymaster 60000
#设置自动故障转移超时
sentinel failover-timeout mymaster 180000
#设置同时故障转移个数
sentinel parallel-syncs mymaster 1
```

针对几个监控设置的配置做一下详细说明：

- **sentinel monitor [master-group-name] [ip] [port] [quorum]**

这个命令中【master-group-name】是 master redis 的名称；【ip】和【port】分别是其 ip 和端口，很好理解。最后一个参数【quorum】是”投票数“

举个栗子，redis 集群中有3个 sentinel 实例，其中 master 挂掉了，如果这里的票数是2，表示有2个 sentinel 认为 master 挂掉啦，才能被认为是正真的挂掉啦。其中 sentinel 集群中各个 sentinel 之间通过 gossip 协议互相通信。
具体怎样投票还涉及到 redis 集群中的【主观下线】和【客观下线】的概念，后面再详细介绍。

- **down-after-milliseconds**

sentinel 会向 master 发送心跳 PING 来确认 master 是否存活，如果 master 在“一定时间范围”内不回应PONG 或者是回复了一个错误消息，那么这个 sentinel 会主观地认为这个 master 已经不可用了。而这个down-after-milliseconds 就是用来指定这个“一定时间范围”的，单位是毫秒。

- **failover-timeout**

这个参数 redis 官方文档中并未做详细说明，但是很好理解，就是 sentinel 对 redis 节点进行自动故障转移的超时设置，当 failover（故障转移）开始后，在此时间内仍然没有触发任何 failover 操作，当前sentinel  将会认为此次故障转移失败。

- **parallel-syncs**

当新master产生时，同时进行 slaveof 到新 master 并进行同步复制的 slave 个数,也就是同时几个 slave 进行同步。因为在 salve 执行 salveof 与新 master 同步时，将会终止客户端请求，因此这个值需要权衡。此值较大，意味着“集群”终止客户端请求的时间总和和较大，此值较小,意味着“集群”在故障转移期间，多个 salve 向客户端提供服务时仍然使用旧数据。

我们配置三个 sentinel 几点组成一个 sentinel 集群，端口分别是 23679，23680，23681

然后就可以启动 sentinel 集群了

启动 sentinel 有两种方式：

1. `redis-sentinel /path/to/sentinel.conf`
2. `redis-server /path/to/sentinel.conf --sentinel`

这两种启动方式没有区别，按照顺序分别启动三个 sentinel 节点之后，我们任意连接其中的一个 sentinel 节点查看集群关系，如下图：
![image](https://picr.zz.ac/8NhRo6JyHXF0Q-Np86uBecOTYRkOC9xSD3PfwBLkfgY=)

我们连接 26379 这个端口的 sentinel，用 `info sentinel`命令可以看到这个 sentinel 监控的 master redis 服务的 ip，端口，以及 maste 的 slaver 节点数量，以及 sentinel 的数量。

再连接 26380 这个节点试试：

![image](https://picr.zz.ac/ffZduqB2q2sxJ3FqjFlexSAwadpF_XqdCPIAOC0PgxA=)

可以看到结果和上面一样。

**如此，我们的 sentinel 集群也部署完成了**

那么，当前这个 redis sentinel 高可用集群的做种拓扑图如下：

![image](https://picr.zz.ac/toEkRcplt-HMfvqpk19fZmNi2_h84fbt9mLAboHIZe4=)

#### 高可用故障测试

下面我们来测试一下这个高可用方案的实际能力。

我们手动把一主二从中的主节点 kill 掉：

![image](https://picr.zz.ac/CJGGUEeOBbpIwEdaWE-IXFlYipPE8Fd8s4z-whfpW_E=)

然后连接 6380 节点，查看集群状态：
![image](https://picr.zz.ac/7TSVcfZ1yee-i__hv8m26Bre9Ll1BvgnnBUO5V0NHMY=)

可以看到 6380 节点已经自动升级为了 master 节点，还有 6381 这一个 slaver 节点，**自动故障转移成功**

我们再手动启动 6379 节点，观察集群状态：

![image](https://picr.zz.ac/6NHFhbKTW8S_-mrHxq1YjTv5kH19UalYpM3228OBa8Y=)

如图，6379节点重新启动后，自动变成了 6380 节点的从节点。

**如此一套完整的 redis 高可用方案就部署完成了。**

#### Redis 主观下线和客观下线

前面说过， Redis 的 Sentinel 中关于下线（down）有两个不同的概念：

- 主观下线（Subjectively Down， 简称 SDOWN）指的是单个 Sentinel 实例对服务器做出的下线判断。
- 客观下线（Objectively Down， 简称 ODOWN）指的是多个 Sentinel 实例在对同一个服务器做出 SDOWN 判断， 并且通过 SENTINEL is-master-down-by-addr 命令互相交流之后， 得出的服务器下线判断。 （一个 Sentinel 可以通过向另一个 Sentinel 发送 SENTINEL is-master-down-by-addr 命令来询问对方是否认为给定的服务器已下线）

如果一个服务器没有在 master-down-after-milliseconds 选项所指定的时间内， 对向它发送 PING 命令的 Sentinel 返回一个有效回复（valid reply）， 那么 Sentinel 就会将这个服务器标记为主观下线。

服务器对 PING 命令的有效回复可以是以下三种回复的其中一种：

- 返回 +PONG 。
- 返回 -LOADING 错误。
- 返回 -MASTERDOWN 错误。

如果服务器返回除以上三种回复之外的其他回复， 又或者在指定时间内没有回复 PING 命令， 那么 Sentinel 认为服务器返回的回复无效（non-valid）。

注意， 一个服务器必须在 master-down-after-milliseconds 毫秒内， 一直返回无效回复才会被 Sentinel 标记为主观下线。

举个栗子， 如果 master-down-after-milliseconds 选项的值为 30000 毫秒（30 秒）， 那么只要服务器能在每 29 秒之内返回至少一次有效回复， 这个服务器就仍然会被认为是处于正常状态的。

从主观下线状态切换到客观下线状态并没有使用严格的法定人数算法（strong quorum algorithm）， 而是使用了流言协议： 如果 Sentinel 在给定的时间范围内， 从其他 Sentinel 那里接收到了足够数量的主服务器下线报告， 那么 Sentinel 就会将主服务器的状态从主观下线改变为客观下线。 如果之后其他 Sentinel 不再报告主服务器已下线， 那么客观下线状态就会被移除。

有一点需要注意的是：客观下线条件**只适用于主服务器**： 对于任何其他类型的 Redis 实例， Sentinel 在将它们判断为下线前不需要进行协商， 所以从服务器或者其他 Sentinel 永远不会达到客观下线条件。

只要一个 Sentinel 发现某个主服务器进入了客观下线状态， 这个 Sentinel 就可能会被其他 Sentinel 推选出， 并对失效的主服务器执行自动故障迁移操作。

### Redis 分布式高可用方案：Redis Cluster

#### 原理简介

作为一个内存数据库，实现高可用是一个基本保障，当储存服务在可预见的将来需要做存储拓展时，分布式储存就是一个必须要考虑到的事情。例如部署一个中央 redis 储存服务，提供给集团下所有的子公司所有需要的系统使用，并且系统数量在不断的增加，此时在部署服务的时候，分布式储存结构几乎是必然的选择。

**Redis 3.0 版本之前，可以通过前面说所的 Redis Sentinel（哨兵）来实现高可用 ( HA )，从 3.0 版本之后，官方推出了Redis Cluster，它的主要用途是实现数据分片(Data Sharding)，同时提供了完整的 sharding、replication（复制机制仍使用原有机制，并且具备感知主备的能力）、failover 解决方案，称为 Redis Cluster，同样可以实现 HA，是官方当前推荐的方案。**

在 Redis Sentinel 模式中，每个节点需要保存全量数据，冗余比较多，而在Redis Cluster 模式中，每个分片只需要保存一部分的数据，对于内存数据库来说，还是要尽量的减少冗余。在数据量太大的情况下，故障恢复需要较长时间，另外，内存的价格也是非常高昂的。

Redis Cluste r的具体实现细节是采用了 Hash 槽的概念，集群会预先分配16384个槽（**slot**），并将这些槽分配给具体的服务节点，通过对 Key 进行 CRC16(key)%16384 运算得到对应的槽是哪一个，从而将读写操作转发到该槽所对应的服务节点。当有新的节点加入或者移除的时候，再来迁移这些槽以及其对应的数据。在这种设计之下，我们就可以很方便的进行动态扩容或缩容。

当然，关于高可用的实现方案，也可以将 Redis-Sentinel 和 Redis-Cluster 两种模式结合起来使用，不过比较复杂，并不太推荐。

下图展示了 Redis Cluster 分配 key 和 slot 的基本原理：

![redis cluster原理图](https://picr.zz.ac/vdyuvUXf_-OIPn-odw5z2FfUIHR8N3MtUzu7tExkkOY=)

一个典型的 Redis Cluster 分布式集群由多个Redis节点组成。不同的节点组服务的数据无交集，每个节点对应数据 sharding 的一个分片。节点组内部分为主备 2 类，对应前面叙述的 master 和 slave。两者数据准实时一致，通过异步化的主备复制机制保证。一个节点组有且仅有一个 master，同时有0到多个 slave。**只有 master 对外提供写服务，读服务可由 master/slave 提供**。如下所示：

![Redis Cluster 拓扑结构](https://picr.zz.ac/BcDoAe20rQv_tWCSi77C7fr9vJepVUyNoRxoYD2sGPc=)

上图中，key-value 全集被分成了 5 份，5个 slot（实际上Redis Cluster有 16384 [0-16383] 个slot，每个节点服务一段区间的slot，这里面仅仅举例）。A和B为master节点，对外提供写服务。分别负责 1/2/3 和 4/5 的slot。A/A1 和B/B1/B2 之间通过主备复制的方式同步数据。

上述的5个节点，两两通过 Redis Cluster Bus 交互，相互交换如下的信息：

1、数据分片（slot）和节点的对应关系；

2、集群中每个节点可用状态；

3、集群结构发生变更时，通过一定的协议对配置信息达成一致。数据分片的迁移、主备切换、单点 master 的发现和其发生主备关系变更等，都会导致集群结构变化。

4、publish/subscribe（发布订阅）功能，在Cluster版内部实现所需要交互的信息。

Redis Cluster Bus 通过单独的端口进行连接，由于Bus是节点间的内部通信机制，交互的是字节序列化信息。相对 Client 的字符序列化来说，效率较高。

Redis Cluster是一个**去中心化**的分布式实现方案，客户端和集群中任一节点连接，然后通过后面的交互流程，逐渐的得到全局的数据分片映射关系。

更多更详细的 redis cluster 的说明请移步[Redis Cluster 官方文档](https://redis.io/topics/cluster-tutorial)

#### 部署实例

Redis Cluster 集群**至少需要三个 master 节点**，本文将以单机多实例的方式部署3个主节点及3个从节点，6个节点实例分别使用不同的端口及工作目录

安装 redis 同上，不赘述。

1. 为每个 redis 节点分别创建工作目录

在redis安装目录 /usr/local/redis-5.0.2 下新建目录 redis-cluster，并在该目录下再新建6个子目录，7000,7001,8000,8001,9000,9001，此时目录结构如下图所示：

![image](https://picr.zz.ac/DLTHB_uBsCrlqUDGdup-zpygiGySXTY2BpK0UHtRqYg=)

2. 修改配置

```shell
#开启后台运行
daemonize yes
#工作端口
port 7000
#绑定机器的内网IP或者公网IP,一定要设置，不要用 127.0.0.1
bind 172.27.0.8  
#指定工作目录，rdb,aof持久化文件将会放在该目录下，不同实例一定要配置不同的工作目录
dir /usr/local/redis-cluster/7000/
#启用集群模式
cluster-enabled yes 
#生成的集群配置文件名称，集群搭建成功后会自动生成，在工作目录下
cluster-config-file nodes-7000.conf 
#节点宕机发现时间，可以理解为主节点宕机后从节点升级为主节点时间
cluster-node-timeout 5000 
#开启AOF模式
appendonly yes 
#pid file所在目录
pidfile /var/run/redis_8001.pid 
```

3. 按照上面的样例将配置文件复制到另外5个目录下，并对 port、dir、cluster-config-file 三个属性做对应修改，这里就不一一列举了。

4. 安装 Ruby 和 RubyGems

由于创建 redis cluster 需要用到 redis-trib 命令，而这个命令依赖 Ruby 和 RubyGems，因此需要安装一下。

```shell
[root@VM_0_15_centos redis-cluster]# yum install ruby
[root@VM_0_15_centos redis-cluster]# yum install rubygems
[root@VM_0_15_centos redis-cluster]# gem install redis --version 3.3.3
```

5. 分别启动6个节点

```shell
[root@VM_0_15_centos redis-4.0.6]# ./src/redis-server redis-cluster/7000/redis.conf
[root@VM_0_15_centos redis-4.0.6]# ./src/redis-server redis-cluster/7001/redis.conf
[root@VM_0_15_centos redis-4.0.6]# ./src/redis-server redis-cluster/8000/redis.conf
[root@VM_0_15_centos redis-4.0.6]# ./src/redis-server redis-cluster/8001/redis.conf
[root@VM_0_15_centos redis-4.0.6]# ./src/redis-server redis-cluster/9000/redis.conf
[root@VM_0_15_centos redis-4.0.6]# ./src/redis-server redis-cluster/9001/redis.conf
```

6. 查看服务运行状态

```shell
[root@VM_0_15_centos redis-4.0.6]# ps -ef | grep redis
root     20290     1  0 18:33 ?        00:00:02 ./src/redis-server *:8001 [cluster]
root     20295     1  0 18:33 ?        00:00:02 ./src/redis-server *:8002 [cluster]
root     20300     1  0 18:33 ?        00:00:02 ./src/redis-server *:8003 [cluster]
root     20305     1  0 18:33 ?        00:00:02 ./src/redis-server *:8004 [cluster]
root     20310     1  0 18:33 ?        00:00:02 ./src/redis-server *:8005 [cluster]
root     20312     1  0 18:33 ?        00:00:02 ./src/redis-server *:8006 [cluster]
root     22913 15679  0 19:31 pts/2    00:00:00 grep --color=auto redis
```

可以看到6个节点以及全部成功启动

7. 创建 redis cluster

```
[root@VM_0_15_centos redis-4.0.6]# ./src/redis-trib.rb create --replicas 1 172.27.0.8:7000 172.27.0.8:7001 172.27.0.8:8000 172.27.0.8:8001 172.27.0.8:9000 172.27.0.8:90001
```

创建过程中会有部分需要确认的地方，按照提示输入即可，集群创建完毕后观察一下这个集群的节点状态

```shell
172.27.0.8:7000> cluster nodes
068ac2afe1ade8b69b83226453fecc2b79cd93ae 172.27.0.8:7001@17001 slave 421ebe9e0a5ac6c811935ecd9dba83ef119dec17 0 1531008204920 4 connected
784c727c83a5952d3714ac211021f909cc4dfee4 172.27.0.8:8001@18001 slave eb5d700e2f030c02fb1f30ba4420d0b4f7170d84 0 1531008203000 5 connected
0537099e7cc7ab595c7aad5f0c96985251b85ec0 172.27.0.8:9001@19001 slave 79262341417df0a11eaf31e72bbf3e26f5f60ebf 0 1531008204419 6 connected
421ebe9e0a5ac6c811935ecd9dba83ef119dec17 172.27.0.8:7000@17000 myself,master - 0 1531008204000 1 connected 0-5460
eb5d700e2f030c02fb1f30ba4420d0b4f7170d84 172.27.0.8:8000@18000 master - 0 1531008203000 2 connected 5461-10922
79262341417df0a11eaf31e72bbf3e26f5f60ebf 172.27.0.8:9000@19000 master - 0 1531008203419 3 connected 10923-16383
```

如上所示，一个 3主3从的 redis cluster 分布式集群就搭建成功了，7000、8000、9000分别是三个 master 节点，7001、8001和9001为对应的 slaver 节点。

其实如果你并不想管这么多配置而只是想在最快的速度内创建一个 redis cluster 用作测试或者其他用途， redis 官方在 redis 安装目录的 Utils 目录下提供了一个 create-cluster 的脚本，如下图：

![image](https://picr.zz.ac/G11VwMOymDU1pf6LbmrWv9NmoX_fYWq0ZVkEWIg6fe8=)

只要执行一下这个脚本就能自动创建一个 cluster

进入到这个目录下，执行`./create-cluster start`，即可立即完成一个 三主三从的 redis-cluster 的搭建：

![image](https://picr.zz.ac/d7GD8jrlbgeoWGhhnNIpdRwCKlKw7v4b9gdp3t9cU84=)

如下图所示就是直接使用这个脚本创建的 redis cluster：

![image](https://picr.zz.ac/i3tcfLLaf_wOKoNI30Rx8a5HlWanF1rFdW2j7x7jJ28=)

#### Tips

1. 如果想重新创建集群，需要登录到每个节点，执行 flushdb，然后执行cluster reset，重启节点；

2. 如果要批量杀掉Redis进程，可以使用 pkill redis-server命令；

3. 如果redis开启了密码认证，则需要在redis.conf中增加属性 : masterauth yourpassword ，并且需要修改/usr/local/share/gems/gems/redis-3.3.3/lib/redis目录下的client.rb文件，将password属性设置为redis.conf中的requirepass的值，不同的操作系统client.rb的位置可能不一样，可以使用 find / -name "client.rb"全盘查找一下；

```bash
 DEFAULTS = {
      :url => lambda { ENV["REDIS_URL"] },
      :scheme => "redis",
      :host => "127.0.0.1",
      :port => 6379,
      :path => nil,
      :timeout => 5.0,
      :password => "yourpassword",
      :db => 0,
      :driver => nil,
      :id => nil,
      :tcp_keepalive => 0,
      :reconnect_attempts => 1,
      :inherit_socket => false
    }
```

4. Redis开启密码认证后，在集群操作时问题会比较多，因此在非特殊情况下不建议开启密码认证，可以搭配使用防火墙保证 Redis 的安全。

故障测试的方法与上面一样，故不赘述。

### 总结

Redis 服务的部署方案的选型大家根据自己项目的需求部署即可，一般来说 redis sentinel 就够用了，也是目前用得最多的模式，但是 redis 3.0 之后官方推出的 redis-cluster 虽然本质是用于实现数据分片和分布式存储，但是其也实现了 redis sentinel 的全部功能，有完全的 HA 能力，并且部署起来更简单，因此成为了官方推荐的 HA 方案。我个人也更加推荐 redis cluster 方案。