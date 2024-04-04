// from https://gist.github.com/ulisesantana/59b7fbdd35512ff8939dc6966a663f86
import { Readable, pipeline } from 'stream'
import fs from 'fs'
import path from 'path'
import { EOL } from 'os'

function createTransaction () {
  return {
    date: new Date(Math.random() * 100_000_000_000),
    type: Math.random() > 0.5 ? 'INCOME' : 'OUTCOME',
    amount: +(Math.random() * 100).toFixed(2)
  }
}

function * iterateTo (limit) {
  for (let index = 1; index <= limit; index++) {
    yield index
  }
}

function numberWithThousandSeparator (x) {
  return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')
}

function logProgress (index, logLimit, startLoop) {
  console.log(`Created ${
      numberWithThousandSeparator(index)
    } records for huge JSON. (${
      numberWithThousandSeparator(logLimit)
    } in ${(Date.now() - startLoop) / 1000} seconds.)`
  )
}

function generateTransactions (limit) {
  return async function * (source) {
    const logLimit = 1_000_000
    let startTime = Date.now()
    for await (const index of source) {
      if (index === 1) {
        yield Buffer.from(`[${EOL}`)
      }
      if (index % logLimit === 0) {
        logProgress(index, logLimit, startTime)
        startTime = Date.now()
      }
      yield Buffer.from(JSON.stringify(createTransaction(), null, 2) + (index === limit ? `${EOL}]` : `,${EOL}`))
    }
  }
}

function onFinish (limit, startTime) {
  return (error) => {
    if (error) {
      console.error(`Error generating JSON file: ${error.toString()}`)
    } else {
      console.log(`Generated ${numberWithThousandSeparator(limit)} records for huge JSON in ${(Date.now() - startTime) / 1000} seconds.`)
    }
  }
}

async function main () {
  const [_node, _module, filePath] = process.argv
  const outputPath = path.resolve(filePath)
  if (fs.existsSync(outputPath)) {
    await fs.promises.unlink(outputPath)
  }
  const limit = 10_000_000
  const startTime = Date.now()
  pipeline(
    Readable.from(iterateTo(limit)),
    generateTransactions(limit),
    fs.createWriteStream(outputPath),
    onFinish(limit, startTime)
  )
}

try {
  await main()
} catch (error) {
  console.error(error.toString())
  console.error('Error generating JSON.')
}
