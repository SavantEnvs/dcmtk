// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
///////////////////////////////////////////////////////////////////////////
#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <new>

#include "dcmtk/dcmdata/dctk.h"
#include "dcmtk/dcmdata/dcistrmb.h"
#include "dcmtk/dcmdata/dcxfer.h"
#include "dcmtk/dcmdata/dcrledrg.h"
#include "dcmtk/dcmimage/diregist.h"
#include "dcmtk/dcmimgle/dcmimage.h"
#include "dcmtk/dcmimgle/diutils.h"
#include "dcmtk/dcmjpeg/djdecode.h"
#include "dcmtk/dcmjpls/djdecode.h"


static void cleanupCodecs() {
  DJDecoderRegistration::cleanup();
  DJLSDecoderRegistration::cleanup();
  DcmRLEDecoderRegistration::cleanup();
}

static bool registerCodecs() {
  DJDecoderRegistration::registerCodecs();
  DJLSDecoderRegistration::registerCodecs();
  DcmRLEDecoderRegistration::registerCodecs();
  std::atexit(cleanupCodecs);
  return true;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  static bool codecs_set = registerCodecs();
  (void)codecs_set;

  DcmInputBufferStream in;
  in.setBuffer((void*)data, size);
  in.setEos();

  DcmFileFormat file;
  const Uint32 kMaxReadLen = 256 * 1024;

  if (file.read(in, EXS_Unknown, EGL_noChange, kMaxReadLen).bad()) return -1;
  {
    if (auto* ds = file.getDataset()) {
      DicomImage* image = new DicomImage(&file, ds->getOriginalXfer());
      if (image && image->getStatus() == EIS_Normal) {
        unsigned long frames = image->getFrameCount();
        if (frames > 16) frames = 16;
        for (unsigned long f = 0; f < frames; ++f)
          (void)image->getOutputData(8, f);
      }
      delete image;
    }
  }
  return 0;
}
